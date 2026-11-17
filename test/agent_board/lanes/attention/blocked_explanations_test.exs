defmodule AgentBoard.Lanes.Attention.BlockedExplanationsTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Attention.Blocked

  @now ~U[2026-11-17 12:00:00Z]
  @opts [now: @now, tz_offset: 0, agent: :unknown]

  test "only blocked candidates inspect their tickets and all retain their position and fields" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    review = %{kind: :review, task: %{number: 7}}
    blocked = %{kind: :blocked, task: %{number: 12}, marker: :retained}
    question = %{kind: :question, task: %{number: 9}}

    tickets = %{
      7 => :must_not_read,
      9 => :must_not_read,
      12 => %{
        "id" => "t12",
        "assignments" => [
          %{"ended_reason" => "retried", "report" => "failed"},
          %{"state" => "pending"}
        ]
      }
    }

    assert [^review, explained, ^question] =
             Blocked.explain([review, blocked, question], tickets, @opts)

    assert Map.delete(explained, :block) == blocked
    assert explained.block.line == "**Retry queued.** Waiting for a free worker (1 of 3)."
    assert explained.block.ticket_id == "t12"
  end

  test "a selected block without a ticket retains an explicit missing explanation" do
    candidate = %{kind: :blocked, task: %{number: 12}}
    assert Blocked.explain([candidate], %{}, @opts) == [Map.put(candidate, :block, nil)]
  end

  test "an empty selection needs no explanation" do
    assert Blocked.explain([], %{12 => :must_not_read}, @opts) == []
  end
end
