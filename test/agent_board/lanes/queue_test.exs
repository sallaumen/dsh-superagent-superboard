defmodule AgentBoard.Lanes.QueueTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Queue

  test "what a task unblocks takes precedence over its split origin" do
    assert Queue.relationship(12, 7) == {:unblocks, 12}
    assert Queue.relationship(12, nil) == {:unblocks, 12}
  end

  test "an origin is shown on its own and a missing relationship stays absent" do
    assert Queue.relationship(nil, 7) == {:split_from, 7}
    assert Queue.relationship(nil, nil) == nil
  end
end
