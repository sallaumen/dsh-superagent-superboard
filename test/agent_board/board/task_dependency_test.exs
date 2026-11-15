defmodule AgentBoard.Board.TaskDependencyTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.TaskDependency

  test "merged and closed tasks resolve a dependency; queued and running tasks still block" do
    resolved = TaskDependency.resolved_blocker_states()

    assert "done" in resolved
    assert "closed" in resolved
    refute "queued" in resolved
    refute "running" in resolved
  end
end
