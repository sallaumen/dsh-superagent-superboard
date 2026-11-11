defmodule AgentBoard.Usage.TaskCosts do
  @moduledoc """
  What each task's executors cost, for a row that cannot read the ledger on
  every render: the same executions as the Executions tab
  (`AgentBoard.Usage.Report.executions/2`, 90 UTC days), summed per task and
  per executor, never across executors (DeepSeek is an estimate, Claude Code
  a list price, Codex has no price).

  `refresh/1` runs after each ledger refresh (`AgentBoard.Usage.Worker`, every
  five minutes) and keeps the result in memory. Before the first run after a
  boot a task has no value: absent, never zero.
  """

  import Ecto.Query, only: [from: 2]

  alias AgentBoard.{AgentState, Repo}
  alias AgentBoard.Board.Task
  alias AgentBoard.Usage.Report

  @key {__MODULE__, :costs}
  @days 90
  @order %{"dsh" => 0, "claude_code" => 1, "codex" => 2}

  @type entry :: %{
          source: String.t(),
          executions: pos_integer(),
          cost: %{micros: non_neg_integer(), complete?: boolean()} | nil,
          unpriced: non_neg_integer()
        }

  @doc """
  Recompute every task's cost from the ledger and keep it. Options: `:since`
  (a UTC date), `:tickets` (the runner's, for the exact harness attribution)
  and `:now`.
  """
  @spec refresh(keyword()) :: :ok
  def refresh(opts \\ []) do
    since = Keyword.get_lazy(opts, :since, fn -> Report.since(@days) end)
    tickets = Keyword.get_lazy(opts, :tickets, &AgentState.tickets/0)

    by_task =
      since
      |> Report.executions(tickets: tickets)
      |> Enum.reject(&is_nil(&1.task_id))
      |> Enum.group_by(& &1.task_id)
      |> Map.new(fn {task_id, executions} -> {task_id, entries(executions)} end)

    :persistent_term.put(@key, %{
      at: Keyword.get(opts, :now, DateTime.utc_now()),
      by_task: by_task
    })

    :ok
  end

  @doc "The entries of each task that has any, by task id."
  @spec for_tasks([integer()]) :: %{integer() => [entry()]}
  def for_tasks(task_ids), do: Map.take(stored().by_task, task_ids)

  @doc """
  The entries of each pull's task, by pull number: the first issue it closes
  that the board tracks, the task its row opens. Pulls of one repository; a
  pull with no such task or no cost is absent.
  """
  @spec for_pulls([map()]) :: %{integer() => [entry()]}
  def for_pulls([]), do: %{}

  def for_pulls([%{repository_id: repository_id} | _] = pulls) do
    numbers = Enum.flat_map(pulls, &(&1.closes_issues || []))

    task_ids =
      Map.new(
        Repo.all(
          from t in Task,
            where:
              t.repository_id == ^repository_id and t.kind == "issue" and t.number in ^numbers,
            select: {t.number, t.id}
        )
      )

    costs = stored().by_task

    for pull <- pulls,
        task_id = Enum.find_value(pull.closes_issues || [], &task_ids[&1]),
        entries = costs[task_id],
        into: %{},
        do: {pull.number, entries}
  end

  @doc "When the values were computed, or nil before the first run."
  @spec computed_at() :: DateTime.t() | nil
  def computed_at, do: stored().at

  @doc false
  def clear, do: :persistent_term.erase(@key)

  defp stored, do: :persistent_term.get(@key, %{at: nil, by_task: %{}})

  # One entry per executor: the sum of the priced executions and how many
  # had no price. Codex has none: its executions are all unpriced.
  defp entries(executions) do
    executions
    |> Enum.group_by(& &1.source)
    |> Enum.map(fn {source, mine} ->
      priced = Enum.filter(mine, & &1.cost)

      %{
        source: source,
        executions: length(mine),
        unpriced: length(mine) - length(priced),
        cost:
          if priced != [] do
            %{
              micros: Enum.sum(Enum.map(priced, & &1.cost.micros)),
              complete?: Enum.all?(priced, & &1.cost.complete?)
            }
          end
      }
    end)
    |> Enum.sort_by(&Map.get(@order, &1.source, 9))
  end
end
