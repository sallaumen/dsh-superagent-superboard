defmodule AgentBoard.Lanes.MergeHistoryTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.MergeHistory

  test "west of UTC the previous local day ends the seven-day window" do
    window = MergeHistory.window(~U[2026-01-01 00:10:00Z], 180)
    assert window.today == ~D[2025-12-31]
    assert Enum.to_list(window.dates) == Enum.to_list(Date.range(~D[2025-12-25], ~D[2025-12-31]))
    assert window.since == ~U[2025-12-25 03:00:00Z]
  end

  test "east of UTC local midnight may fall on the preceding UTC date" do
    window = MergeHistory.window(~U[2025-12-31 18:30:00Z], -330)
    assert window.today == ~D[2026-01-01]
    assert Enum.to_list(window.dates) == Enum.to_list(Date.range(~D[2025-12-26], ~D[2026-01-01]))
    assert window.since == ~U[2025-12-25 18:30:00Z]
  end

  test "daily totals count issues once and distinguish local evidence from remote checks" do
    pulls = [
      %{number: 1, closes_issues: [7, 8], checks_state: "failure"},
      %{number: 2, closes_issues: [8], checks_state: "success"},
      %{number: 3, closes_issues: [], checks_state: "success"},
      %{number: 4, closes_issues: nil, checks_state: "failure"}
    ]

    local = %{
      1 => %{state: :pass},
      2 => %{state: :fail},
      3 => %{state: :stale},
      9 => %{state: :fail}
    }

    assert MergeHistory.day_totals(pulls, local) == %{n: 4, issues: 2, ok: 1, fail: 1}
    assert %{ok: 1, fail: 0} = MergeHistory.day_totals([hd(pulls)], local)
    assert MergeHistory.day_totals([], local) == %{n: 0, issues: 0, ok: 0, fail: 0}
  end

  test "the whole window does not sum the per-day counts for a repeated issue" do
    monday = [%{closes_issues: [7, 8]}]
    tuesday = [%{closes_issues: [8, 12]}]
    assert MergeHistory.delivered(monday ++ tuesday) == 3
  end
end
