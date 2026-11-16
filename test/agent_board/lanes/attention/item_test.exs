defmodule AgentBoard.Lanes.Attention.ItemTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Lanes.Attention.Item

  @now ~U[2026-11-16 12:00:00Z]

  test "a review carries the task identity and content but reads CI by pull number" do
    task = %{id: 71, number: 12, title: "Review work", state_changed_at: DateTime.add(@now, -60)}
    pull = %PullRequest{number: 8, checks_state: "success"}

    ctx = %{
      now: @now,
      last_visit: task.state_changed_at,
      local_ci: %{8 => %{state: :fail, detail: "tests failed"}}
    }

    actions = [%{task_id: 71}]

    assert %{
             key: "task-71",
             id: 71,
             number: 12,
             kind: :review,
             title: "Review work",
             why: "Ready",
             actions: ^actions,
             age_seconds: 60,
             is_new: false,
             pull_number: 8,
             ci: %{state: "fail"}
           } =
             Item.build(task, :review, pull, {"Ready", actions}, ctx)
  end

  test "a silent run becomes new at the threshold, with no guessed pull or CI" do
    task = %{id: 71, number: 12, title: "Run"}

    ctx = %{
      now: @now,
      last_visit: DateTime.add(@now, -40),
      stall_after: 90,
      silences: %{12 => %{at: DateTime.add(@now, -120)}}
    }

    assert %{age_seconds: 30, is_new: true, ci: nil, pull_number: nil} =
             Item.build(task, :stalled, nil, {"Last signal", []}, ctx)
  end
end
