defmodule AgentBoard.Lanes.Attention.BlockedTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.Task
  alias AgentBoard.Lanes
  alias AgentBoard.Lanes.Attention.Blocked

  @at ~U[2026-11-07 17:10:00Z]
  @task %Task{id: 17, repository_id: 3, number: 61, title: "Blocked task", inserted_at: @at}

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "the failure line and retry button belong to the same blocked ticket" do
    ticket = %{
      "id" => "ticket-61",
      "assignments" => [
        %{
          "id" => "a1",
          "report" => "failed",
          "summary" => "LlmError: DeepSeek Messages transport failed",
          "report_at" => @at
        }
      ]
    }

    [card] =
      Lanes.needs(%{id: 3}, %{blocked: [@task]},
        now: @at,
        tz_offset: 180,
        tickets_by_number: %{61 => ticket}
      )

    assert card.why == "**Network failure calling the model.** Automatic retry at 14:11 (1 of 3)."

    assert card.actions == [
             %{label: "Try now", retry: %{ticket_id: "ticket-61", repository_id: 3, number: 61}},
             %{label: "View details", task_id: 17}
           ]
  end

  test "a queued retry explains the wait and offers only the detail action" do
    ticket = %{
      "id" => "ticket-61",
      "assignments" => [
        %{"id" => "a1", "ended_reason" => "retried", "report" => "failed"},
        %{"state" => "pending"}
      ]
    }

    [card] =
      Lanes.needs(%{id: 3}, %{blocked: [@task]}, now: @at, tickets_by_number: %{61 => ticket})

    assert card.why == "**Retry queued.** Waiting for a free worker (1 of 3)."
    assert card.actions == [%{label: "View details", task_id: 17}]
  end

  test "an unexplained block, a missing label or a missing ticket only offers details" do
    for block <- [nil, %{retry: nil, ticket_id: "t7"}, %{retry: "Try again", ticket_id: nil}] do
      assert Blocked.actions(@task, block) == [%{label: "View details", task_id: 17}]
    end
  end
end
