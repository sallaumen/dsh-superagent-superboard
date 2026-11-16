defmodule AgentBoard.Lanes.MergeHistory.VisibleCostsTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.MergeHistory
  alias AgentBoard.Lanes.MergeHistory.Calendar
  alias AgentBoard.Usage.TaskCosts

  test "a hidden PR counts for the week but cannot trigger a cost lookup for unlinked visible PRs" do
    at = ~U[2026-01-01 12:00:00Z]
    base = %{repository_id: 1, merged_at: at, closes_issues: [], number: 10}
    yesterday = %{base | merged_at: DateTime.add(at, -1, :day)}

    today =
      for n <- 1..9 do
        issues =
          cond do
            n == 9 -> [42]
            rem(n, 2) == 0 -> nil
            true -> []
          end

        %{base | number: n, closes_issues: issues}
      end

    calendar = Calendar.build(today ++ [yesterday], MergeHistory.window(at, 0), %{})
    visible = Calendar.visible_pulls(calendar)
    assert calendar.issues == 1
    assert Enum.map(visible, & &1.number) == [10 | Enum.to_list(1..8)]
    assert TaskCosts.for_pulls(visible) == %{}
  end
end
