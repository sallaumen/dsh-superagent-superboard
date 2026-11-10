defmodule AgentBoard.Conversation.Lookup do
  @moduledoc """
  The facts behind a spoken question the snapshot cannot answer: one task in
  depth, the agent's runs, what is failing, a search, the day and the week.

  Everything here is a read of the board's own data (the database, the
  runner's ticket file, the voice activity ring). Nothing costs a call and
  nothing is written. The facts go to the `:voice_explain` call, which
  answers only from them; ages come precomputed in minutes so the model
  never does date arithmetic.

  Titles, bodies, reports and comments are copied as data and cut short.
  """

  import Ecto.Query, warn: false

  alias AgentBoard.{AgentState, AgentWorktree, Board, Repo, Tickets, Workpad}
  alias AgentBoard.Board.{Comment, PullRequest, Repository, Task}
  alias AgentBoard.Voice.Activity

  @sample 8
  @search_rows 1_000
  @day_seconds 24 * 3600
  @stopwords ~w(tarefa tarefas sobre para com que uma tem algum alguma acha achar busca buscar
                procura procurar onde qual quais the and for about with task tasks find search
                bug bugs aberto aberta abertos issue issues)

  @type args :: %{optional(:task_number) => integer(), optional(:query) => String.t()}
  @type outcome ::
          {:ok, map(), nil | {:open_task, Task.t()}}
          | {:error, :task_not_found | :no_repository | :empty_query | :unknown_lookup}

  @doc """
  The facts for one lookup kind (see `AgentBoard.Voice.Commands.lookups/0`).
  `ctx` is the conversation context (`repo`, `repos`, `board`, `open_task`,
  `tz_offset`, `now`); the third element is an effect for the screen.
  """
  @spec facts(String.t(), map(), args()) :: outcome()
  def facts(kind, ctx, args \\ %{})

  def facts("task", ctx, args) do
    case task(ctx, args[:task_number]) do
      %Task{} = task -> {:ok, task_facts(task, now(ctx)), {:open_task, task}}
      nil -> {:error, :task_not_found}
    end
  end

  def facts("runs", ctx, _args), do: {:ok, runs_facts(ctx, now(ctx)), nil}

  def facts("failures", %{repo: %Repository{}} = ctx, _args),
    do: {:ok, failures_facts(ctx, now(ctx)), nil}

  def facts("search", ctx, args) do
    case words(args[:query]) do
      [] -> {:error, :empty_query}
      words -> {:ok, search_facts(ctx, words, now(ctx)), nil}
    end
  end

  def facts("activity", %{repo: %Repository{}} = ctx, _args),
    do: {:ok, activity_facts(ctx, now(ctx)), nil}

  def facts(kind, _ctx, _args) when kind in ~w(failures activity), do: {:error, :no_repository}
  def facts(_kind, _ctx, _args), do: {:error, :unknown_lookup}

  # ---- one task -------------------------------------------------------------

  defp task(ctx, number) when is_integer(number) and number > 0 do
    case ctx[:repo] do
      %Repository{} = repo -> Board.find_task(repo, number)
      _ -> nil
    end
  end

  defp task(ctx, _number), do: ctx[:open_task]

  defp task_facts(task, now) do
    comments = Board.comments(task)
    pull = Board.task_pull_request(task, comments)
    ticket = ticket_for(task)
    workpad = Board.agent_workpad(task.repository_id, task.number)

    %{
      number: task.number,
      title: task.title,
      state: task.state,
      in_state_minutes: minutes(task.state_changed_at || task.inserted_at, now),
      created_minutes_ago: minutes(task.inserted_at, now),
      started_minutes_ago: minutes(task.started_at, now),
      stopped: task.stopped,
      archived: task.archived,
      request: cut(task.body, 400),
      workpad: workpad_fact(workpad),
      run: ticket_fact(ticket, now),
      pull_request: pull_fact(pull, now),
      recent_comments:
        comments
        |> Enum.take(-3)
        |> Enum.map(&comment_fact(&1, now))
    }
  end

  defp workpad_fact(nil), do: nil

  defp workpad_fact(workpad) do
    %{
      blockage: cut(workpad.blockage, 400),
      question: cut(workpad.question, 300),
      plan: cut(workpad.plan, 300)
    }
  end

  defp comment_fact(%Comment{} = comment, now) do
    workpad? = not is_nil(Workpad.parse(comment.body))

    %{
      from: comment.kind,
      minutes_ago: minutes(comment.inserted_at, now),
      workpad: workpad?,
      text: if(workpad?, do: nil, else: cut(comment.body, 300))
    }
  end

  defp pull_fact(nil, _now), do: nil

  defp pull_fact(%PullRequest{} = pull, now) do
    %{
      number: pull.number,
      state: pull.state,
      review: pull.review_state,
      checks: pull.checks_state,
      failed_checks: pull.checks_failed,
      checks_changed_minutes_ago: minutes(pull.checks_changed_at, now)
    }
  end

  # ---- runs -----------------------------------------------------------------

  defp runs_facts(ctx, now) do
    snapshot = AgentState.snapshot()
    by_number = snapshot.tickets |> own_tickets(ctx[:repo]) |> Tickets.by_number()
    board = ctx[:board] || %{}
    counts = Map.get(board, :task_counts) || %{}
    running = Map.get(board, :running) || []

    %{
      agent: %{
        source_readable: snapshot.ok,
        last_signal_minutes_ago: minutes(snapshot.at, now),
        open_runs: Enum.count(snapshot.tickets, &is_nil(&1["ended_at"]))
      },
      running_total: Map.get(counts, :running, length(running)),
      queued_total: Map.get(counts, :queued, 0),
      running:
        running
        |> Enum.take(@sample)
        |> Enum.map(fn task ->
          ticket = Map.get(by_number, task.number)

          %{
            number: task.number,
            title: task.title,
            running_minutes: minutes(task.started_at, now),
            run: ticket_fact(ticket, now),
            last_step: step_fact(ticket)
          }
        end),
      ended_last_24h: ended(snapshot.tickets, now)
    }
  end

  defp ended(tickets, now) do
    since = DateTime.add(now, -@day_seconds, :second)

    tickets
    |> Enum.filter(&(&1["ended_at"] && DateTime.compare(&1["ended_at"], since) == :gt))
    |> Enum.sort_by(& &1["ended_at"], {:desc, DateTime})
    |> Enum.take(@sample)
    |> Enum.map(fn ticket ->
      %{
        numbers: ticket["numbers"],
        title: ticket["title"],
        outcome: ticket["ended_outcome"],
        minutes_ago: minutes(ticket["ended_at"], now)
      }
    end)
  end

  defp step_fact(ticket) do
    case AgentWorktree.step(ticket) do
      %{kind: kind, code: code, note: note} -> %{kind: kind, file_or_commit: code, note: note}
      _ -> nil
    end
  end

  # ---- failures -------------------------------------------------------------

  defp failures_facts(ctx, now) do
    repo = ctx.repo
    snapshot = AgentState.snapshot()
    tickets = own_tickets(snapshot.tickets, repo)
    by_number = Tickets.by_number(tickets)
    board = ctx[:board] || %{}

    %{
      failing_checks:
        Repo.all(
          from p in PullRequest,
            where:
              p.repository_id == ^repo.id and p.state == "open" and
                p.checks_state == "failure",
            order_by: [desc: p.checks_changed_at, desc: p.id],
            limit: @sample
        )
        |> Enum.map(fn pull ->
          %{
            number: pull.number,
            title: pull.title,
            failed_checks: pull.checks_failed,
            minutes_ago: minutes(pull.checks_changed_at, now)
          }
        end),
      blocked:
        (Map.get(board, :blocked) || [])
        |> Enum.take(@sample)
        |> Enum.map(fn task ->
          workpad = Board.agent_workpad(task.repository_id, task.number)

          %{
            number: task.number,
            title: task.title,
            blocked_minutes: minutes(task.state_changed_at, now),
            blockage: workpad && cut(workpad.blockage, 300),
            run: ticket_fact(Map.get(by_number, task.number), now)
          }
        end),
      # An open run whose last report failed: the board retries a transient
      # one by itself (AgentBoard.AutoRetry); the rest wait for a person.
      failed_runs:
        tickets
        |> Enum.filter(&(&1["report"] == "failed" and is_nil(&1["ended_at"])))
        |> Enum.take(@sample)
        |> Enum.map(fn ticket ->
          %{
            numbers: ticket["numbers"],
            title: ticket["title"],
            summary: cut(ticket["report_summary"], 300),
            minutes_ago: minutes(ticket["report_at"], now)
          }
        end),
      runs_ended_without_merge:
        snapshot.tickets
        |> ended(now)
        |> Enum.reject(&(&1.outcome in ["merged", "completed"])),
      sync: sync_fact(Board.latest_sync(repo), now),
      voice_errors:
        Activity.recent()
        |> Enum.filter(&(&1.status == :error))
        |> Enum.take(5)
        |> Enum.map(&%{stage: &1.stage, detail: &1.detail, minutes_ago: minutes(&1.at, now)}),
      agent_source_readable: snapshot.ok
    }
  end

  defp sync_fact(nil, _now), do: nil

  defp sync_fact(event, now) do
    %{
      failed: event.kind == "sync_error",
      minutes_ago: minutes(event.inserted_at, now),
      reason: event.kind == "sync_error" && cut(inspect_reason(event.payload), 200)
    }
  end

  defp inspect_reason(%{"reason" => reason}) when is_binary(reason), do: reason
  defp inspect_reason(payload), do: inspect(payload)

  # ---- search ---------------------------------------------------------------

  @doc false
  def words(nil), do: []

  def words(query) do
    query
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.filter(&(String.length(&1) >= 3 and &1 not in @stopwords))
    |> Enum.uniq()
    |> Enum.take(5)
  end

  defp search_facts(ctx, words, now) do
    repo_ids = search_scope(ctx)

    # Matched here, not in SQL: accents fold the same way on both sides
    # ("botao" finds "botão") without a database extension. The newest rows
    # are enough for a spoken search.
    tasks =
      Repo.all(
        from t in Task,
          join: r in Repository,
          on: r.id == t.repository_id,
          where: t.repository_id in ^repo_ids and t.kind == "issue",
          order_by: [desc: t.updated_at, desc: t.id],
          limit: @search_rows,
          select: {t, r.name}
      )
      |> Enum.map(fn {task, name} -> {score(task.title, task.body, words), task, name} end)
      |> Enum.filter(fn {score, _task, _name} -> score > 0 end)
      |> Enum.sort_by(fn {score, _task, _name} -> -score end)
      |> Enum.take(@sample)
      |> Enum.map(fn {_score, task, name} ->
        %{
          project: name,
          number: task.number,
          title: task.title,
          state: task.state,
          updated_minutes_ago: minutes(task.updated_at, now)
        }
      end)

    pulls =
      Repo.all(
        from p in PullRequest,
          join: r in Repository,
          on: r.id == p.repository_id,
          where: p.repository_id in ^repo_ids,
          order_by: [desc: p.updated_at, desc: p.id],
          limit: @search_rows,
          select: {p, r.name}
      )
      |> Enum.filter(fn {pull, _name} -> score(pull.title, nil, words) > 0 end)
      |> Enum.take(5)
      |> Enum.map(fn {pull, name} ->
        %{
          project: name,
          number: pull.number,
          title: pull.title,
          state: pull.state,
          checks: pull.checks_state
        }
      end)

    %{
      searched_words: words,
      scope: if(length(repo_ids) == 1, do: "current project", else: "all projects"),
      tasks: tasks,
      pull_requests: pulls
    }
  end

  # The current project first; every tracked project when none is selected.
  defp search_scope(%{repo: %Repository{id: id}}), do: [id]
  defp search_scope(ctx), do: Enum.map(ctx[:repos] || [], & &1.id)

  # A title hit counts twice a body hit: the owner names a task by its title.
  defp score(title, body, words) do
    title = fold(title)
    body = fold(body)

    Enum.reduce(words, 0, fn word, acc ->
      acc + if(String.contains?(title, word), do: 2, else: 0) +
        if String.contains?(body, word), do: 1, else: 0
    end)
  end

  defp fold(nil), do: ""

  defp fold(text),
    do: text |> String.downcase() |> String.normalize(:nfd) |> String.replace(~r/\p{Mn}/u, "")

  # ---- the day and the week -------------------------------------------------

  defp activity_facts(ctx, now) do
    repo_id = ctx.repo.id
    offset = ctx[:tz_offset] || 0
    today = AgentBoard.Time.local_date(now, offset)
    day_start = local_midnight(today, offset)
    week_start = local_midnight(Date.add(today, -6), offset)
    board = ctx[:board] || %{}
    counts = Map.get(board, :task_counts) || %{}

    %{
      today: %{
        merged: merged(repo_id, day_start),
        created: created(repo_id, day_start),
        runs_ended:
          AgentState.tickets()
          |> Enum.filter(&(&1["ended_at"] && DateTime.compare(&1["ended_at"], day_start) != :lt))
          |> Enum.frequencies_by(&(&1["ended_outcome"] || "unknown"))
      },
      last_7_days: %{
        merged_count: merged_count(repo_id, week_start),
        created_count: created_count(repo_id, week_start)
      },
      lanes_now: Map.new(counts, fn {lane, n} -> {lane, n} end)
    }
  end

  defp local_midnight(date, offset),
    do: date |> DateTime.new!(~T[00:00:00Z]) |> DateTime.add(offset * 60, :second)

  defp merged(repo_id, since) do
    rows =
      Repo.all(
        from p in PullRequest,
          where: p.repository_id == ^repo_id and p.state == "merged" and p.merged_at >= ^since,
          order_by: [desc: p.merged_at],
          select: %{number: p.number, title: p.title}
      )

    %{count: length(rows), sample: Enum.take(rows, 5)}
  end

  defp created(repo_id, since) do
    rows =
      Repo.all(
        from t in Task,
          where: t.repository_id == ^repo_id and t.kind == "issue" and t.inserted_at >= ^since,
          order_by: [desc: t.inserted_at],
          select: %{number: t.number, title: t.title, state: t.state}
      )

    %{count: length(rows), sample: Enum.take(rows, 5)}
  end

  defp merged_count(repo_id, since) do
    Repo.aggregate(
      from(p in PullRequest,
        where: p.repository_id == ^repo_id and p.state == "merged" and p.merged_at >= ^since
      ),
      :count
    )
  end

  defp created_count(repo_id, since) do
    Repo.aggregate(
      from(t in Task,
        where: t.repository_id == ^repo_id and t.kind == "issue" and t.inserted_at >= ^since
      ),
      :count
    )
  end

  # ---- shared ---------------------------------------------------------------

  defp ticket_for(task) do
    AgentState.tickets()
    |> own_tickets(Board.repository(task.repository_id))
    |> Tickets.by_number()
    |> Map.get(task.number)
  end

  # Issue numbers repeat across repositories; without one (Today) all count.
  defp own_tickets(tickets, nil), do: tickets

  defp own_tickets(tickets, repo),
    do: Enum.filter(tickets, &AgentState.same_repository?(&1, repo))

  defp ticket_fact(nil, _now), do: nil

  defp ticket_fact(ticket, now) do
    %{
      assignment: ticket["assignment"],
      report: ticket["report"],
      report_summary: cut(ticket["report_summary"], 300),
      report_minutes_ago: minutes(ticket["report_at"], now),
      ended: ticket["ended_outcome"],
      stopped: ticket["stopped"]
    }
  end

  defp minutes(nil, _now), do: nil
  defp minutes(%NaiveDateTime{} = at, now), do: minutes(DateTime.from_naive!(at, "Etc/UTC"), now)
  defp minutes(%DateTime{} = at, now), do: max(div(DateTime.diff(now, at, :second), 60), 0)

  defp now(ctx), do: ctx[:now] || DateTime.utc_now()

  defp cut(nil, _max), do: nil

  defp cut(text, max) do
    text = text |> String.replace(~r/<!--.*?-->/s, "") |> String.trim()

    cond do
      text == "" -> nil
      String.length(text) <= max -> text
      true -> String.slice(text, 0, max) <> "…"
    end
  end
end
