defmodule AgentBoard.Lanes.RunningAttentionTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.{Repository, Task}
  alias AgentBoard.Lanes
  alias AgentBoard.Lanes.Attention

  @now ~U[2026-11-07 12:00:00Z]
  @run %Task{id: 1, number: 11, size: "S", state_changed_at: DateTime.add(@now, -1200)}

  test "silence wins when both thresholds are met; only elapsed evidence qualifies" do
    signal = %{seconds: 900, at: DateTime.add(@now, -900), source: :report}
    assert Attention.running_kind(@run, signal, 900, @now) == :stalled

    assert Attention.running_kind(
             @run,
             %{signal | seconds: 899, at: DateTime.add(@now, -899)},
             900,
             @now
           ) == :slow

    assert Attention.running_kind(@run, nil, 900, DateTime.add(@now, -1)) == nil
  end

  test "an equally new unanswered call follows the silence, and a long run appears last" do
    since = DateTime.add(@now, -900)
    queued = %Task{id: 3, number: 13, held: false, released_at: since}
    board = %{running: [%{@run | id: 2, number: 12}, @run], queued: [queued]}

    opts = [
      now: @now,
      last_visit: DateTime.add(@now, -1),
      stall_after: 900,
      silences: %{11 => %{seconds: 900, at: since, source: :report}}
    ]

    needs = Lanes.needs(%Repository{owner: "fixture", name: "board"}, board, opts)

    assert Enum.map(needs, &{&1.number, &1.kind, &1.age_seconds, &1.is_new}) ==
             [{11, :stalled, 0, true}, {13, :unanswered, 0, true}, {12, :slow, 0, true}]
  end
end
