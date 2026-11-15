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
end
