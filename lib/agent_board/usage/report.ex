defmodule AgentBoard.Usage.Report do
  @moduledoc """
  The usage ledger as numbers a screen, the router or the summary of the day
  can read: per execution, per task, per day and per executor.

  Every value keeps its source's currency and its class:

    * the harness's US$ is **estimated** from the board's price table, each
      token at the rate of its hour (DeepSeek charges half outside its peak);
    * Claude Code's US$ is an **estimated list price** of the Claude Max
      subscription, a reference and not a bill; its real quota is **unknown**;
    * Codex has no US$: it is a **measured** share of the weekly window;
    * a source with no reading is **unknown**, never zero.

  The ledger rows are read once and aggregated in memory: the table holds one
  row per execution and UTC day, and a 30-day window is a few thousand rows.
  Attribution is `AgentBoard.Attribution` over the session's cwd, branch and
  (for a harness ticket) its execution folder.
  """

  import Ecto.Query

  alias AgentBoard.AI.Providers
  alias AgentBoard.{Attribution, Board, Repo}
  alias AgentBoard.Usage.{Costs, Harness, Ledger}

  @default_days 30
  @source_order %{"dsh" => 0, "claude_code" => 1, "codex" => 2}

  @type cost :: %{micros: non_neg_integer(), complete?: boolean(), currency: :usd}
  @type execution :: %{
          source: String.t(),
          execution_id: String.t(),
          requests: non_neg_integer(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cache_read_tokens: non_neg_integer(),
          cache_write_tokens: non_neg_integer(),
          models: [String.t()],
          cwd: String.t() | nil,
          git_branch: String.t() | nil,
          first_at: DateTime.t() | nil,
          last_at: DateTime.t() | nil,
          days: pos_integer(),
          cost: cost() | nil,
          attribution: Attribution.result(),
          task_id: integer() | nil,
          repository_id: integer() | nil,
          repository: String.t() | nil,
          outside: String.t() | nil,
          exact: boolean()
        }

  @doc "The first day of a window of `days` UTC dates, today included."
  @spec since(integer()) :: Date.t()
  def since(days \\ @default_days), do: Date.add(Date.utc_today(), -(days - 1))

  @doc "The ledger rows from `since` (a UTC date) on, oldest first."
  @spec rows(Date.t(), Date.t() | nil) :: [map()]
  def rows(since, until \\ nil) do
    from(l in "usage_ledger",
      where: l.day >= ^since,
      order_by: [asc: l.day, asc: l.source, asc: l.execution_id],
      select: %{
        source: l.source,
        execution_id: l.execution_id,
        day: l.day,
        cwd: l.cwd,
        git_branch: l.git_branch,
        model: l.model,
        requests: l.requests,
        input_tokens: l.input_tokens,
        output_tokens: l.output_tokens,
        cache_read_tokens: l.cache_read_tokens,
        cache_write_tokens: l.cache_write_tokens,
        cache_write_1h_tokens: l.cache_write_1h_tokens,
        first_at: type(l.first_at, :utc_datetime_usec),
        last_at: type(l.last_at, :utc_datetime_usec)
      }
    )
    |> maybe_until(until)
    |> Repo.all()
    |> with_peak(since, until)
  end

  # A ledger row sums a day, and DeepSeek charges by the hour: each harness
  # row gets the tokens of its peak hours, from its own messages.
  defp with_peak(rows, since, until) do
    if Enum.any?(rows, &(&1.source == "dsh")) do
      peak = peak_by_row(since, until)
      Enum.map(rows, &put_peak(&1, peak))
    else
      rows
    end
  end

  defp put_peak(%{source: "dsh"} = row, peak),
    do: Map.put(row, :peak, Map.get(peak, row_key(row)))

  defp put_peak(row, _peak), do: row

  defp row_key(row), do: {row.execution_id, row.day, row.cwd, row.git_branch, row.model}

  # Grouped by hour in the database; which hours are peak stays one rule
  # (`Providers.peak?/1`).
  defp peak_by_row(since, until) do
    from(m in "usage_messages",
      where: m.source == "dsh" and m.day >= ^since,
      group_by: [
        m.execution_id,
        m.day,
        m.cwd,
        m.git_branch,
        m.model,
        fragment("date_trunc('hour', ?)", m.at)
      ],
      select: %{
        execution_id: m.execution_id,
        day: m.day,
        cwd: m.cwd,
        git_branch: m.git_branch,
        model: m.model,
        hour: type(fragment("date_trunc('hour', ?)", m.at), :utc_datetime_usec),
        input: type(sum(m.input_tokens), :integer),
        output: type(sum(m.output_tokens), :integer),
        cache_read: type(sum(m.cache_read_tokens), :integer)
      }
    )
    |> messages_until(until)
    |> Repo.all()
    |> Enum.reduce(%{}, fn bucket, acc ->
      add =
        if Providers.peak?(bucket.hour), do: bucket, else: %{input: 0, output: 0, cache_read: 0}

      Map.update(
        acc,
        row_key(bucket),
        Map.take(add, [:input, :output, :cache_read]),
        &%{
          input: &1.input + add.input,
          output: &1.output + add.output,
          cache_read: &1.cache_read + add.cache_read
        }
      )
    end)
  end

  defp messages_until(query, nil), do: query
  defp messages_until(query, %Date{} = until), do: where(query, [m], m.day <= ^until)

  defp maybe_until(query, nil), do: query
  defp maybe_until(query, %Date{} = until), do: where(query, [l], l.day <= ^until)

  @doc """
  One row per execution (a Claude Code session, a Codex thread, a harness
  ticket), newest first, with cost, tokens and attribution.
  """
  @spec executions(Date.t(), keyword()) :: [execution()]
  def executions(since, opts \\ []) do
    index = Keyword.get_lazy(opts, :index, &Board.attribution_index/0)
    tickets = Keyword.get(opts, :tickets, [])
    rows = rows(since)
    names = repository_names()
    exact = exact_tasks(rows, tickets)

    rows
    |> Enum.group_by(&{&1.source, &1.execution_id})
    |> Enum.map(fn {{source, execution_id}, members} ->
      first = hd(members)
      session = %{cwd: first[:cwd], git_branch: first[:git_branch]}
      session = Map.put(session, :task_id, Map.get(exact, {source, execution_id}))
      attribution = Attribution.for_session(session, index)
      {task_id, repository_id, outside, exact?} = attribution_fields(attribution)

      %{
        source: source,
        execution_id: execution_id,
        requests: sum(members, :requests),
        input_tokens: sum(members, :input_tokens),
        output_tokens: sum(members, :output_tokens),
        cache_read_tokens: sum(members, :cache_read_tokens),
        cache_write_tokens: sum(members, :cache_write_tokens),
        models: models(members),
        cwd: first[:cwd],
        git_branch: first[:git_branch],
        first_at:
          members
          |> Enum.map(& &1[:first_at])
          |> Enum.reject(&is_nil/1)
          |> Enum.min(DateTime, fn -> nil end),
        last_at:
          members
          |> Enum.map(& &1[:last_at])
          |> Enum.reject(&is_nil/1)
          |> Enum.max(DateTime, fn -> nil end),
        days: members |> Enum.map(& &1.day) |> Enum.uniq() |> length(),
        cost: Costs.cost(source, members),
        attribution: attribution,
        task_id: task_id,
        repository_id: repository_id,
        repository: Map.get(names, repository_id),
        outside: outside,
        exact: exact?
      }
    end)
    |> Enum.sort_by(&{&1.source, &1.execution_id})
  end

  @doc "The executions attributed to a task, newest first."
  @spec by_task(integer(), keyword()) :: [execution()]
  def by_task(task_id, opts \\ []) do
    since = Keyword.get_lazy(opts, :since, fn -> Date.add(Date.utc_today(), -90) end)

    since
    |> executions(opts)
    |> Enum.filter(&(&1.task_id == task_id))
    |> Enum.sort_by(& &1.last_at, {:desc, DateTime})
  end

  @doc """
  One summary per executor for the panel: sessions, tasks, direct sessions by
  repository, sessions outside the board, tokens, the cost in the executor's
  own currency, and how many of its tasks merged and how long that took.
  """
  @spec executors(Date.t(), keyword()) :: [map()]
  def executors(since, opts \\ []) do
    executions = executions(since, opts)
    tasks = task_refs(executions)
    merged = merged_by_task(tasks)
    quota = Costs.codex_weekly(Ledger.limits())

    @source_order
    |> Enum.sort_by(fn {_source, rank} -> rank end)
    |> Enum.map(fn {source, _rank} ->
      mine = Enum.filter(executions, &(&1.source == source))
      summary(source, mine, tasks, merged, quota)
    end)
  end

  defp summary(source, executions, tasks, merged, quota) do
    task_ids = executions |> Enum.map(& &1.task_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    merged_tasks = Enum.filter(task_ids, &Map.has_key?(merged, &1))
    hours = Enum.map(merged_tasks, &Map.fetch!(merged, &1))

    cost =
      case Enum.filter(executions, & &1.cost) do
        [] ->
          nil

        priced ->
          %{
            micros: Enum.sum(Enum.map(priced, & &1.cost.micros)),
            complete?: Enum.all?(priced, & &1.cost.complete?),
            unknown: length(executions) - length(priced)
          }
      end

    %{
      source: source,
      executions: length(executions),
      tasks:
        task_ids
        |> Enum.map(&Map.get(tasks, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.number, :desc)
        |> Enum.take(8),
      tasks_count: length(task_ids),
      direct: frequency(executions, &direct_repository/1),
      outside: frequency(executions, fn execution -> execution.outside end),
      unknown: Enum.count(executions, &(&1.attribution == :unknown)),
      requests: sum(executions, :requests),
      input_tokens: sum(executions, :input_tokens),
      output_tokens: sum(executions, :output_tokens),
      cache_read_tokens: sum(executions, :cache_read_tokens),
      cache_write_tokens: sum(executions, :cache_write_tokens),
      models: executions |> Enum.flat_map(& &1.models) |> Enum.uniq() |> Enum.sort(),
      cost: cost,
      quota: if(source == "codex", do: quota),
      merged: %{
        tasks: length(task_ids),
        merged: length(merged_tasks),
        rate: if(task_ids == [], do: nil, else: length(merged_tasks) / length(task_ids)),
        median_hours: median(hours)
      }
    }
  end

  defp task_refs(executions) do
    ids = executions |> Enum.map(& &1.task_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      %{}
    else
      Repo.all(
        from t in "tasks",
          where: t.id in type(^ids, {:array, :integer}),
          select: %{
            id: t.id,
            number: t.number,
            title: t.title,
            state: t.state,
            repository_id: t.repository_id,
            inserted_at: t.inserted_at
          }
      )
      |> Map.new(&{&1.id, &1})
    end
  end

  # The earliest merged PR that closes each task's issue, per task id, in
  # hours from the task's creation.
  defp merged_by_task(tasks) do
    list = Map.values(tasks)

    pulls =
      if list == [] do
        []
      else
        repo_ids = list |> Enum.map(& &1.repository_id) |> Enum.uniq()

        Repo.all(
          from p in "pull_requests",
            where: p.repository_id in ^repo_ids and not is_nil(p.merged_at),
            order_by: [asc: p.merged_at],
            select: %{
              repository_id: p.repository_id,
              merged_at: type(p.merged_at, :utc_datetime),
              closes_issues: p.closes_issues
            }
        )
      end

    list
    |> Enum.flat_map(fn task ->
      case merged_hours(task, pulls) do
        nil -> []
        hours -> [{task.id, hours}]
      end
    end)
    |> Map.new()
  end

  defp merged_hours(task, pulls) do
    pulls
    |> Enum.filter(
      &(&1.repository_id == task.repository_id and task.number in (&1.closes_issues || []))
    )
    |> Enum.map(& &1.merged_at)
    |> Enum.min(fn -> nil end)
    |> case do
      nil -> nil
      at -> seconds_between(at, task.inserted_at) / 3600
    end
  end

  defp seconds_between(a, b),
    do: NaiveDateTime.diff(to_naive(a), to_naive(b), :second)

  defp to_naive(%DateTime{} = at), do: DateTime.to_naive(at)
  defp to_naive(%NaiveDateTime{} = at), do: at

  defp direct_repository(%{attribution: {:repository, _id}, repository: name}), do: name
  defp direct_repository(_execution), do: nil

  defp frequency(executions, fun) do
    executions
    |> Enum.map(fun)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {name, count} -> {-count, name} end)
  end

  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values)
    middle = div(length(sorted), 2)

    if rem(length(sorted), 2) == 0 do
      (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
    else
      Enum.at(sorted, middle)
    end
  end

  @doc """
  One row per source and UTC day, with the day's cost and tokens. The sources
  are never added together.
  """
  @spec daily(Date.t()) :: [map()]
  def daily(since) do
    since
    |> rows()
    |> Enum.group_by(&{&1.source, &1.day})
    |> Enum.map(fn {{source, day}, members} ->
      %{
        source: source,
        day: day,
        requests: sum(members, :requests),
        executions: members |> Enum.map(& &1.execution_id) |> Enum.uniq() |> length(),
        input_tokens: sum(members, :input_tokens),
        output_tokens: sum(members, :output_tokens),
        cache_read_tokens: sum(members, :cache_read_tokens),
        cache_write_tokens: sum(members, :cache_write_tokens),
        models: models(members),
        cost: Costs.cost(source, members)
      }
    end)
    |> Enum.sort_by(&{&1.day, Map.get(@source_order, &1.source, 9)})
  end

  @doc """
  Today's spending in each executor's own currency, for the "Hoje" view.

  "Today" is the owner's day: `offset` is minutes west of UTC, the same
  convention as `AgentBoard.Time.local/2` and the browser's
  `getTimezoneOffset()`. The ledger's days are UTC, so the window is the local
  day's two UTC instants; the newest weekly Codex quota comes with it. A
  source with no row says "não rodou", never zero. `:now` is for tests.
  """
  @spec today(integer(), keyword()) :: %{day: Date.t(), by_source: map(), quota: map() | nil}
  def today(offset \\ 0, opts \\ []) when is_integer(offset) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    local = DateTime.add(now, -offset * 60, :second)
    day = DateTime.to_date(local)
    since = local_day_start(day, offset)
    until = DateTime.add(since, 86_400, :second)
    lines = spend_window(since, until)

    %{
      day: day,
      by_source:
        Map.new(lines, fn {source, line} -> {source, Map.put(line, :source, source)} end),
      quota: Costs.codex_weekly(Ledger.limits())
    }
  end

  defp local_day_start(day, offset) do
    day
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.add(offset * 60, :second)
  end

  @doc """
  The median cost of an execution of each executor in the last 30 days, in
  the executor's own currency. `:unknown` when there is no priced history;
  Codex has no US$ and always answers `:unknown`.
  """
  @spec expected_costs(keyword()) :: %{optional(String.t()) => term()}
  def expected_costs(opts \\ []) do
    days = Keyword.get(opts, :days, @default_days)

    executions =
      rows(since(days))
      |> Enum.group_by(&{&1.source, &1.execution_id})
      |> Enum.map(fn {{source, _id}, members} -> {source, Costs.cost(source, members)} end)

    %{
      "dsh" => median_cost(executions, "dsh"),
      "claude" => list_cost(median_cost(executions, "claude_code")),
      "codex" => :unknown
    }
  end

  defp median_cost(executions, source) do
    costs =
      for {^source, %{micros: micros} = cost} <- executions,
          micros > 0,
          do: Map.put(cost, :micros, micros)

    case costs do
      [] ->
        :unknown

      costs ->
        sorted = Enum.sort_by(costs, & &1.micros)
        middle = div(length(sorted), 2)

        if rem(length(sorted), 2) == 0 do
          a = Enum.at(sorted, middle - 1)
          b = Enum.at(sorted, middle)
          %{a | micros: div(a.micros + b.micros, 2), complete?: a.complete? and b.complete?}
        else
          Enum.at(sorted, middle)
        end
    end
  end

  defp list_cost(%{micros: _micros} = cost), do: Map.put(cost, :reference, :list)
  defp list_cost(other), do: other

  @doc """
  What each executor spent between two instants, for the summary of the day:
  one map per source, in its own currency, never added together.
  """
  @spec spend_window(DateTime.t(), DateTime.t()) :: %{optional(String.t()) => map()}
  def spend_window(%DateTime{} = since, %DateTime{} = until) do
    %{
      "dsh" => messages_window("dsh", since, until),
      "claude_code" => messages_window("claude_code", since, until),
      "codex" => codex_window(since, until)
    }
  end

  defp messages_window(source, since, until) do
    messages =
      Repo.all(
        from m in "usage_messages",
          where: m.source == ^source and m.at >= ^since and m.at < ^until,
          select: %{
            source: m.source,
            model: m.model,
            at: type(m.at, :utc_datetime_usec),
            requests: 1,
            input_tokens: m.input_tokens,
            output_tokens: m.output_tokens,
            cache_read_tokens: m.cache_read_tokens,
            cache_write_tokens: m.cache_write_tokens,
            cache_write_1h_tokens: m.cache_write_1h_tokens
          }
      )

    line(source, messages)
  end

  defp codex_window(since, until) do
    rows =
      Repo.all(
        from l in "usage_ledger",
          where: l.source == "codex" and l.last_at >= ^since and l.first_at < ^until,
          select: %{
            source: l.source,
            model: l.model,
            requests: l.requests,
            input_tokens: l.input_tokens,
            output_tokens: l.output_tokens,
            cache_read_tokens: l.cache_read_tokens,
            cache_write_tokens: l.cache_write_tokens
          }
      )

    line("codex", rows)
    |> Map.put(:quota, Costs.codex_weekly(Ledger.limits()))
  end

  defp line(source, [] = _rows) do
    if seen?(source),
      do: %{source: source, status: :none, requests: 0},
      else: %{source: source, status: :unknown, reason: :no_source, requests: 0}
  end

  defp line(source, rows) do
    %{
      source: source,
      status: :measured,
      requests: sum(rows, :requests),
      models: models(rows),
      cost: Costs.cost(source, rows),
      currency: if(source in Costs.usd_sources(), do: :usd)
    }
  end

  defp seen?("codex") do
    Repo.exists?(from l in "usage_ledger", where: l.source == "codex")
  end

  defp seen?(source) do
    Repo.exists?(from m in "usage_messages", where: m.source == ^source)
  end

  # A harness ticket names its folder under ~/.dsh/sessions; the ledger keeps
  # that folder as the execution, so a live ticket maps it back to its issue.
  defp exact_tasks(rows, tickets) do
    dsh = Enum.filter(rows, &(&1.source == "dsh"))

    if dsh == [] or tickets == [] do
      %{}
    else
      dsh
      |> Enum.flat_map(&exact_task_rows(&1, tickets))
      |> Map.new()
    end
  end

  defp exact_task_rows(row, tickets), do: Enum.flat_map(tickets, &exact_task_row(row, &1))

  defp exact_task_row(row, ticket) do
    directory = get_in(ticket, ["execution", "directory"])

    if is_binary(directory) and
         Path.basename(Harness.transcript_dir(directory)) == row.execution_id do
      task_ids(ticket, row)
    else
      []
    end
  end

  defp task_ids(ticket, row) do
    for number <- ticket["numbers"] || [],
        task_id = task_id_for_number(number),
        task_id != nil,
        do: {{"dsh", row.execution_id}, task_id}
  end

  # A ticket number with more than one task on the board is ambiguous and
  # picks none: the board never guesses which repository it came from.
  defp task_id_for_number(number) do
    tasks =
      Repo.all(
        from t in "tasks",
          where: t.number == ^number and t.kind == "issue" and not is_nil(t.number),
          select: t.id
      )

    case tasks do
      [id] -> id
      _ -> nil
    end
  end

  defp repository_names do
    Repo.all(from r in "repositories", select: {r.id, r.owner, r.name})
    |> Map.new(fn {id, owner, name} -> {id, "#{owner}/#{name}"} end)
  end

  defp attribution_fields({:task, task_id, _rule}), do: {task_id, nil, nil, true}
  defp attribution_fields({:repository, repository_id}), do: {nil, repository_id, nil, false}
  defp attribution_fields({:outside, name}), do: {nil, nil, name, false}
  defp attribution_fields(:unknown), do: {nil, nil, nil, false}

  defp models(rows) do
    rows
    |> Enum.map(& &1[:model])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp sum(rows, key), do: rows |> Enum.map(&Map.get(&1, key, 0)) |> Enum.sum()
end
