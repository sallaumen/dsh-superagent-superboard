defmodule AgentBoard.Usage.Overview do
  @moduledoc """
  Settings → Costs → Summary: what a window of UTC days cost, each source in
  its own currency and class, never added across currencies.

    * the agent's DeepSeek (`dsh`) and Claude Code come from the usage ledger
      (`Report.daily/1`): US$ estimated, a minimum when a row has no price;
      Claude Code's is a list-price reference, not a bill;
    * Codex is the measured share of its weekly window (`Ledger.limits/0`);
    * the board's own AI calls are `ai_calls.cost_micros`, priced when the
      call ran; a call with tokens and no price makes the total a minimum;
    * ElevenLabs is characters and audio seconds (`ElevenLabs.Usage`), with
      the plan as the board last read it. It has no US$.

  The daily series holds the US$ that leaves a balance (the agent's DeepSeek
  and the board's calls); a source that did not run is `0`, a day it ran
  without a price is `nil`.
  """
  import Ecto.Query

  alias AgentBoard.AI.{Call, Providers}
  alias AgentBoard.Board.Task
  alias AgentBoard.ElevenLabs.{Account, Usage}
  alias AgentBoard.Repo
  alias AgentBoard.Usage.{Costs, Ledger, Report}

  @top_tasks 5

  @doc "The summary for the last `days` UTC days, today included."
  @spec build(pos_integer(), keyword()) :: map()
  def build(days, opts \\ []) do
    since = Report.since(days)
    daily = Report.daily(since)
    executions = Report.executions(since, Keyword.take(opts, [:tickets, :index]))
    board = board_daily(since)

    %{
      days: days,
      since: since,
      today: Date.utc_today(),
      agents: Map.new(["dsh", "claude_code"], &{&1, agent(&1, daily, executions)}),
      peak: peak(since),
      codex: Costs.codex_weekly(Ledger.limits()),
      board_ai: board_total(board),
      voice: Usage.window(since),
      account: Account.snapshot(),
      series: series(since, daily, board),
      top_tasks: top_tasks(executions)
    }
  end

  @doc """
  The sum of several costs: nil when none is priced, a minimum
  (`complete?: false`) when any is missing or incomplete.
  """
  @spec total([map() | nil]) :: %{micros: non_neg_integer(), complete?: boolean()} | nil
  def total(costs) do
    case Enum.reject(costs, &is_nil/1) do
      [] ->
        nil

      priced ->
        %{
          micros: priced |> Enum.map(& &1.micros) |> Enum.sum(),
          complete?: length(priced) == length(costs) and Enum.all?(priced, & &1.complete?)
        }
    end
  end

  defp agent(source, daily, executions) do
    rows = Enum.filter(daily, &(&1.source == source))

    %{
      ran?: rows != [],
      cost: total(Enum.map(rows, & &1.cost)),
      executions: Enum.count(executions, &(&1.source == source)),
      requests: rows |> Enum.map(& &1.requests) |> Enum.sum(),
      output_tokens: rows |> Enum.map(& &1.output_tokens) |> Enum.sum()
    }
  end

  # The share of the agent's DeepSeek cost paid at the peak rate. Peak hours
  # are whole UTC hours, so hourly sums price exactly like single messages.
  defp peak(since) do
    rows =
      Repo.all(
        from m in "usage_messages",
          where: m.source == "dsh" and m.at >= ^start(since),
          group_by: [selected_as(:hour), m.model],
          select: %{
            hour: selected_as(fragment("date_trunc('hour', ?)", m.at), :hour),
            model: m.model,
            input_tokens: type(sum(m.input_tokens), :integer),
            output_tokens: type(sum(m.output_tokens), :integer),
            cache_read_tokens: type(sum(m.cache_read_tokens), :integer),
            cache_write_tokens: type(sum(m.cache_write_tokens), :integer),
            cache_write_1h_tokens: type(sum(m.cache_write_1h_tokens), :integer)
          }
      )
      |> Enum.map(&Map.put(&1, :at, DateTime.from_naive!(&1.hour, "Etc/UTC")))

    case Costs.cost("dsh", rows) do
      %{micros: all} when all > 0 ->
        at_peak = Costs.cost("dsh", Enum.filter(rows, &Providers.peak?(&1.at)))
        %{share: ((at_peak && at_peak.micros) || 0) / all}

      _ ->
        nil
    end
  end

  defp board_daily(since) do
    Repo.all(
      from c in Call,
        where: c.inserted_at >= ^start(since),
        group_by: selected_as(:day),
        select: %{
          day: selected_as(fragment("(?)::date", c.inserted_at), :day),
          calls: count(c.id),
          errors: filter(count(c.id), c.status == "error"),
          micros: type(coalesce(sum(c.cost_micros), 0), :integer),
          # Tokens and no price: the model was missing from the price table.
          unpriced:
            filter(
              count(c.id),
              c.status == "ok" and coalesce(c.input_tokens, 0) + coalesce(c.output_tokens, 0) > 0 and
                coalesce(c.cost_micros, 0) == 0
            )
        }
    )
  end

  defp board_total(rows) do
    calls = rows |> Enum.map(& &1.calls) |> Enum.sum()

    %{
      calls: calls,
      errors: rows |> Enum.map(& &1.errors) |> Enum.sum(),
      cost:
        if(calls > 0,
          do: %{
            micros: rows |> Enum.map(& &1.micros) |> Enum.sum(),
            complete?: Enum.all?(rows, &(&1.unpriced == 0))
          }
        )
    }
  end

  defp series(since, daily, board) do
    agent = for %{source: "dsh"} = row <- daily, into: %{}, do: {row.day, row.cost}
    board = Map.new(board, &{&1.day, &1})

    Enum.map(Date.range(since, Date.utc_today()), fn day ->
      %{
        day: day,
        agent: Map.get(agent, day, %{micros: 0, complete?: true}),
        board:
          case Map.get(board, day) do
            nil -> %{micros: 0, complete?: true}
            row -> %{micros: row.micros, complete?: row.unpriced == 0}
          end
      }
    end)
  end

  defp top_tasks(executions) do
    by_task =
      executions
      |> Enum.filter(&(&1.source == "dsh" and is_integer(&1.task_id)))
      |> Enum.group_by(& &1.task_id, & &1.cost)
      |> Enum.map(fn {task_id, costs} -> {task_id, total(costs)} end)
      |> Enum.reject(fn {_task_id, cost} -> is_nil(cost) end)
      |> Enum.sort_by(fn {_task_id, cost} -> cost.micros end, :desc)
      |> Enum.take(@top_tasks)

    ids = Enum.map(by_task, &elem(&1, 0))

    tasks =
      Repo.all(
        from t in Task,
          join: r in assoc(t, :repository),
          where: t.id in ^ids,
          select: {t.id, %{title: t.title, number: t.number, repository: r.name, owner: r.owner}}
      )
      |> Map.new()

    for {task_id, cost} <- by_task, task = tasks[task_id] do
      Map.merge(task, %{task_id: task_id, cost: cost})
    end
  end

  defp start(day), do: DateTime.new!(day, ~T[00:00:00], "Etc/UTC")
end
