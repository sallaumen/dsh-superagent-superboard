defmodule AgentBoard.Lanes.RunTimingTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.RunTiming

  @start ~U[2026-11-10 12:00:00Z]

  test "each size gets its time allowance, with unknown sizes treated as large" do
    for {size, minutes} <- [{"S", 20}, {"M", 40}, {"L", 60}, {nil, 60}, {"XL", 60}] do
      task = %{size: size, state_changed_at: nil, started_at: @start}
      deadline = DateTime.add(@start, minutes * 60)
      assert RunTiming.slow_at(task) == deadline
      refute RunTiming.slow?(task, DateTime.add(deadline, -1))
      assert RunTiming.slow?(task, deadline)
    end
  end

  test "a resumed run counts from its new start, without counting time spent waiting" do
    resumed = DateTime.add(@start, 3600)
    task = %{size: "S", started_at: @start, state_changed_at: resumed}
    assert RunTiming.slow_at(task) == DateTime.add(resumed, 20 * 60)
    refute RunTiming.slow?(task, resumed)
  end

  test "unknown working time has no deadline" do
    task = %{size: "S", state_changed_at: nil, started_at: nil}
    assert RunTiming.slow_at(task) == nil
    refute RunTiming.slow?(task, @start)
  end
end
