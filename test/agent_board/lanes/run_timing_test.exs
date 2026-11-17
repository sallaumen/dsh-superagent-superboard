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

  test "slow details count a resumed run from its new start" do
    resumed = DateTime.add(@start, 3600)
    task = %{size: "S", started_at: @start, state_changed_at: resumed}

    assert RunTiming.slow_details(task, DateTime.add(resumed, 300)) ==
             %{since: resumed, elapsed_seconds: 300, limit_minutes: 20}
  end

  test "slow details use the original start as fallback and share the size allowance" do
    for {size, minutes} <- [{"S", 20}, {"M", 40}, {"L", 60}, {nil, 60}, {"XL", 60}] do
      task = %{size: size, state_changed_at: nil, started_at: @start}

      assert RunTiming.slow_details(task, DateTime.add(@start, 3600)) ==
               %{since: @start, elapsed_seconds: 3600, limit_minutes: minutes}
    end
  end

  test "missing time stays unknown and a future start never gives a negative duration" do
    task = %{size: nil, state_changed_at: nil, started_at: nil}

    assert RunTiming.slow_details(task, @start) ==
             %{since: nil, elapsed_seconds: nil, limit_minutes: 60}

    future = DateTime.add(@start, 60)

    assert RunTiming.slow_details(%{task | started_at: future}, @start) ==
             %{since: future, elapsed_seconds: 0, limit_minutes: 60}
  end

  describe "the next moment a running task needs attention" do
    @now ~U[2026-11-10 12:00:00.000Z]

    test "is the nearest future limit or silence, in milliseconds" do
      started = DateTime.add(@now, -10 * 60, :second)
      small = %{number: 1, size: "S", state_changed_at: started, started_at: started}
      quiet = %{number: 2, size: "L", state_changed_at: started, started_at: started}
      silences = %{2 => %{at: DateTime.add(@now, -60, :second)}}

      assert RunTiming.next_attention_in([small, quiet], silences, 121, @now) == 61_000
      assert RunTiming.next_attention_in([small], %{}, 121, @now) == 10 * 60 * 1000
    end

    test "a limit under a second away still counts, and a passed one never does" do
      soon = DateTime.add(@now, -(20 * 60) + 1, :second) |> DateTime.add(-500, :millisecond)
      passed = DateTime.add(@now, -30 * 60, :second)

      assert RunTiming.next_attention_in(
               [%{number: 1, size: "S", state_changed_at: soon, started_at: soon}],
               %{},
               60,
               @now
             ) == 500

      assert RunTiming.next_attention_in(
               [%{number: 1, size: "S", state_changed_at: passed, started_at: passed}],
               %{},
               60,
               @now
             ) == nil
    end

    test "an alert due now does not hide a future alert for another task" do
      started = DateTime.add(@now, -20 * 60)
      due = %{number: 1, size: "S", state_changed_at: started, started_at: started}
      later = %{due | number: 2, size: "M"}
      assert RunTiming.next_attention_in([due, later], %{}, 60, @now) == 20 * 60 * 1000
    end

    test "an orphan signal or a task with no timestamps schedules nothing" do
      task = %{number: 8, size: "S", state_changed_at: nil, started_at: nil}
      silences = %{9 => %{at: @now}}
      assert RunTiming.next_attention_in([task], silences, 60, @now) == nil
      assert RunTiming.next_attention_in([], silences, 60, @now) == nil
    end
  end
end
