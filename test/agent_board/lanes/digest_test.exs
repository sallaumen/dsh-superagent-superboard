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

  test "a single known task carries both its link target and its issue number" do
    task = %{id: 71, number: 12}
    assert Digest.task_subject(%{running: [task]}, :running) == {:task, 71, 12}
    assert Digest.task_subject(%{blocked: [task], task_counts: %{blocked: 51}}, :blocked) == 51
  end

  test "one task without a unique visible row stays a count; an empty lane says nothing" do
    assert Digest.task_subject(%{task_counts: %{blocked: 1}}, :blocked) == 1
    assert Digest.task_subject(%{running: [%{}, %{}], task_counts: %{running: 1}}, :running) == 1
    assert Digest.task_subject(%{}, :running) == nil
  end
end
