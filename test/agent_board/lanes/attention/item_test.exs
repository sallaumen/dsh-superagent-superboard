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

  test "recorded questions and blockages use the same task identity but different actions" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    task = %{id: 71, repository_id: 3, number: 12, title: "Check build", state_changed_at: @now}

    ctx = %{
      now: @now,
      last_visit: DateTime.add(@now, -1),
      pulls: %{},
      tickets: %{12 => %{"report_summary" => "Fallback?"}},
      questions: %{12 => "Which build?"},
      blockages: %{3 => %{12 => "Missing key"}, 4 => %{12 => "Other reason"}}
    }

    assert %{
             key: "task-71",
             number: 12,
             kind: :question,
             why: "**The agent asked:** Which build?",
             actions: [%{label: "Respond", task_id: 71}],
             is_new: true
           } =
             Item.build(%{kind: :question, task: task}, ctx)

    assert %{
             key: "task-71",
             kind: :blocked,
             why: "**Blocked:** Missing key",
             actions: [%{label: "View details", task_id: 71}],
             pull_number: nil
           } =
             Item.build(%{kind: :blocked, task: task, block: nil}, ctx)
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
