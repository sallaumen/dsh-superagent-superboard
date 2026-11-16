defmodule AgentBoard.Lanes.DigestTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Digest

  test "first visit uses whole-lane totals and combines work waiting for the owner" do
    board = %{
      running: [%{id: 7}],
      task_counts: %{running: 51, retrying: 2, ready: 3, question: 4, blocked: 8, queued: 9}
    }

    assert Digest.first_visit(board) == [
             running: 51,
             retrying: 2,
             waiting: 7,
             blocked: 8,
             queued: 9
           ]
  end

  test "a snapshot without totals counts the supplied rows, leaving out empty lanes" do
    assert Digest.first_visit(%{ready: [%{}], queued: [%{}, %{}]}) == [waiting: 1, queued: 2]
    assert Digest.first_visit(%{}) == []
  end
end
