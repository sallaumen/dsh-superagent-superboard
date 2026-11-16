defmodule AgentBoard.Lanes.MergeHistory.CalendarTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.MergeHistory

  test "local midnight splits the pages; empty days and all in-window issues contribute to the calendar" do
    window = MergeHistory.window(~U[2026-01-01 04:00:00Z], 180)
    midnight = ~U[2026-01-01 03:00:00Z]

    pulls = [
      %{number: 99, merged_at: window.until, closes_issues: [99]},
      %{number: 2, merged_at: midnight, closes_issues: [2, 7]},
      %{number: 1, merged_at: DateTime.add(midnight, -1), closes_issues: [7]}
    ]

    calendar = MergeHistory.Calendar.build(pulls, window, %{2 => %{state: :fail}})
    assert Enum.map(calendar.days, & &1.summary.date) == Enum.to_list(window.dates)
    {empty, [yesterday, today]} = Enum.split(calendar.days, 5)
    assert Enum.all?(empty, &(&1.summary.n == 0 and &1.page.items == []))

    assert %{summary: %{date: ~D[2025-12-31], n: 1, today: false}, page: %{items: [%{number: 1}]}} =
             yesterday

    assert %{
             summary: %{date: ~D[2026-01-01], n: 1, issues: 2, today: true, fail: 1},
             page: %{items: [%{number: 2}]}
           } = today

    assert calendar.issues == 2
  end

  test "merges beyond the wide page still affect a day's issue and CI counts" do
    at = ~U[2026-01-01 10:00:00Z]
    pulls = for n <- 1..9, do: %{number: n, merged_at: at, closes_issues: [n]}

    calendar =
      MergeHistory.Calendar.build(pulls, MergeHistory.window(at, 0), %{9 => %{state: :pass}})

    day = List.last(calendar.days)
    assert %{n: 9, issues: 9, ok: 1} = day.summary
    assert day.page.more_wide == 1
    assert Enum.map(day.page.items ++ day.page.extra, & &1.number) == Enum.to_list(1..8)
  end
end
