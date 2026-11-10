defmodule AgentBoard.Usage.TaskCostsTest do
  @moduledoc "The executor's cost per task, from the ledger, kept for the rows."
  # The values live in one global term: these tests own it while they run.
  use AgentBoard.DataCase, async: false

  alias AgentBoard.Board
  alias AgentBoard.Board.{PullRequest, Task}
  alias AgentBoard.Usage.{Costs, TaskCosts}

  setup do
    TaskCosts.clear()
    on_exit(&TaskCosts.clear/0)
    :ok
  end

  defp ledger(source, execution, model, branch \\ "feat/mapa") do
    at = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("usage_ledger", [
      %{
        source: source,
        execution_id: execution,
        day: Date.utc_today(),
        cwd: "/tmp/costs",
        git_branch: branch,
        model: model,
        requests: 1,
        input_tokens: 1_000_000,
        output_tokens: 1_000_000,
        cache_read_tokens: 0,
        cache_write_tokens: 0,
        first_at: at,
        last_at: at,
        inserted_at: at,
        updated_at: at
      }
    ])
  end

  setup do
    {:ok, repo} = Board.add_repository("fixture", "costs")

    task =
      %Task{}
      |> Task.changeset(%{repository_id: repo.id, kind: "issue", number: 12, title: "Mapa"})
      |> Repo.insert!()

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 3,
      title: "Mapa",
      state: "merged",
      closes_issues: [12],
      head_ref: "feat/mapa"
    })
    |> Repo.insert!()

    %{task: task}
  end

  test "nothing is known before the first run: absent, not zero", %{task: task} do
    assert TaskCosts.computed_at() == nil
    assert TaskCosts.for_tasks([task.id]) == %{}
  end

  test "each executor of a task is summed apart, and an unpriced one is unknown", %{task: task} do
    ledger("claude_code", "session-1", "claude-opus-5-5")
    ledger("claude_code", "session-2", "claude-opus-5-5")
    ledger("codex", "thread-1", "gpt-5-codex")
    # another branch: not this task
    ledger("claude_code", "session-3", "claude-opus-5-5", "main")

    now = ~U[2026-11-10 21:00:00Z]
    :ok = TaskCosts.refresh(tickets: [], now: now)

    assert TaskCosts.computed_at() == now
    task_id = task.id
    assert %{^task_id => [claude, codex]} = costs = TaskCosts.for_tasks([task_id, -1])
    assert map_size(costs) == 1

    assert %{source: "claude_code", executions: 2, unpriced: 0, cost: %{micros: micros}} = claude
    assert micros > 0

    # the two sessions, and only them
    one =
      Costs.cost("claude_code", [
        %{model: "claude-opus-5-5", input_tokens: 1_000_000, output_tokens: 1_000_000}
      ])

    assert micros == 2 * one.micros
    assert %{source: "codex", executions: 1, unpriced: 1, cost: nil} = codex
  end
end
