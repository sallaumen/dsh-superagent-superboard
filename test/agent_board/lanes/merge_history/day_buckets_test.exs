defmodule AgentBoard.Lanes.MergeHistory.DayBucketsTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.MergeHistory

  test "an empty merge list retains every day in calendar order" do
    window = MergeHistory.window(~U[2026-01-01 04:00:00Z], 180)

    assert MergeHistory.day_buckets([], window) ==
             for(date <- Date.range(~D[2025-12-26], ~D[2026-01-01]), do: {date, []})
  end

  test "local midnight separates days, outside dates are excluded and row order is retained" do
    window = MergeHistory.window(~U[2026-01-01 04:00:00Z], 180)
    midnight = ~U[2026-01-01 03:00:00Z]
    yesterday = %{number: 1, merged_at: DateTime.add(midnight, -1)}
    first = %{number: 2, merged_at: DateTime.add(midnight, 3600)}
    second = %{number: 3, merged_at: midnight}
    third = %{number: 4, merged_at: DateTime.add(midnight, 7200)}

    pulls = [
      %{number: 99, merged_at: window.until},
      first,
      yesterday,
      second,
      third,
      %{number: 98, merged_at: DateTime.add(window.since, -1)}
    ]

    buckets = MergeHistory.day_buckets(pulls, window)
    {empty, last_two} = Enum.split(buckets, 5)
    assert Enum.all?(empty, fn {_date, rows} -> rows == [] end)

    assert last_two == [
             {~D[2025-12-31], [yesterday]},
             {~D[2026-01-01], [first, second, third]}
           ]
  end

  test "a half-hour offset east of UTC still uses the exact local midnight" do
    window = MergeHistory.window(~U[2026-01-01 20:00:00Z], -330)
    previous = %{number: 1, merged_at: ~U[2026-01-01 18:29:59Z]}
    current = %{number: 2, merged_at: ~U[2026-01-01 18:30:00Z]}
    buckets = MergeHistory.day_buckets([current, previous], window)

    assert List.last(buckets) == {~D[2026-01-02], [current]}
    assert Map.new(buckets)[~D[2026-01-01]] == [previous]
  end
end
