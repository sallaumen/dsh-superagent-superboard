defmodule AgentBoard.MetricsTest do
  @moduledoc "The throughput arithmetic: windows, the reader's clock, and what is unknown."
  use ExUnit.Case, async: true

  alias AgentBoard.Metrics

  @now ~U[2026-11-07 01:25:40Z]

  defp at(seconds_ago), do: DateTime.add(@now, -seconds_ago, :second)

  describe "hour_buckets/3" do
    test "ends at now with the current hour partial, oldest first" do
      buckets = Metrics.hour_buckets(@now, 0)

      assert length(buckets) == 24
      assert List.last(buckets) == %{from: ~U[2026-11-07 01:00:00Z], to: @now}

      assert List.first(buckets) == %{
               from: ~U[2026-11-06 02:00:00Z],
               to: ~U[2026-11-06 03:00:00Z]
             }
    end

    test "aligns to the reader's clock, including a half-hour offset" do
      # Minutes west of UTC: São Paulo is 180, India is -330.
      assert %{from: ~U[2026-11-07 01:00:00Z]} = List.last(Metrics.hour_buckets(@now, 180))
      assert %{from: ~U[2026-11-07 00:30:00Z]} = List.last(Metrics.hour_buckets(@now, -330))
    end
  end

  describe "series/2" do
    test "counts each bucket, start inclusive and end exclusive, now inclusive" do
      buckets = Metrics.hour_buckets(@now, 0)

      stamps = [
        # exactly the top of the current hour: the last bucket
        ~U[2026-11-07 01:00:00Z],
        # now itself: still inside
        @now,
        # one second after now: outside every bucket
        DateTime.add(@now, 1, :second),
        # the end of the previous hour belongs to the current one
        ~U[2026-11-07 00:59:59Z],
        # before the window
        ~U[2026-11-06 01:59:59Z]
      ]

      series = Metrics.series(stamps, buckets)
      assert length(series) == 24
      assert List.last(series) == 2
      assert Enum.at(series, 22) == 1
      assert Enum.sum(series) == 3
    end

    test "an empty observation is a flat line" do
      assert Metrics.series([], Metrics.hour_buckets(@now, 0)) == List.duplicate(0, 24)
    end
  end

  describe "within/4" do
    test "is a sliding window ending at now" do
      stamps = [at(0), at(3599), at(3600), at(3601), at(86_399), at(86_400)]

      assert Metrics.within(stamps, @now, 3600) == 2
      assert Metrics.within(stamps, @now, 3600, 3600) == 2
      assert Metrics.within(stamps, @now, 86_400) == 5
      assert Metrics.within(stamps, @now, 7 * 86_400) == 6
    end
  end

  describe "rate_tile/4" do
    test "measures the hour, the previous hour, the day, the week and the trend" do
      stamps = [at(60), at(120), at(4000), at(50_000), at(3 * 86_400)]

      tile =
        Metrics.rate_tile(
          "merged",
          {:ok, stamps},
          @now,
          Metrics.hour_buckets(@now, 0)
        )

      assert tile.status == :measured
      assert tile.hour == 2
      assert tile.previous == 1
      assert tile.delta == 1
      assert tile.day == 4
      assert tile.week == 5
      assert_in_delta tile.day_rate, 4 / 24, 0.0001
      assert_in_delta tile.week_rate, 5 / 168, 0.0001
      assert Enum.sum(tile.series) == 4
    end

    test "an unknown source is unknown, not zero" do
      tile = Metrics.rate_tile("commits", {:unknown, :never_synced}, @now, [])

      assert tile.status == :unknown
      assert tile.reason == :never_synced
      assert tile.hour == nil
      assert tile.series == nil
    end
  end

  describe "depth_at/2 and queue_tile/4" do
    test "counts the spans open at an instant" do
      spans = [
        {at(7200), nil},
        {at(7200), at(1800)},
        {at(600), nil},
        {DateTime.add(@now, 60, :second), nil}
      ]

      assert Metrics.depth_at(spans, @now) == 2
      assert Metrics.depth_at(spans, at(3600)) == 2
      assert Metrics.depth_at(spans, at(1800)) == 1
    end

    test "the tile has the depth now, the delta and the peaks" do
      spans = [{at(10_000), at(5000)}, {at(10_000), at(5000)}, {at(100), nil}]
      tile = Metrics.queue_tile(spans, @now, 0, Metrics.hour_buckets(@now, 0))

      assert tile.hour == 1
      assert tile.previous == 0
      assert tile.delta == 1
      assert tile.day == 2
      assert tile.week == 2
      assert length(tile.series) == 24
      assert List.last(tile.series) == 1
    end

    test "no spans is an empty queue, which is a measurement" do
      tile = Metrics.queue_tile([], @now, 0, Metrics.hour_buckets(@now, 0))
      assert tile.status == :measured
      assert tile.hour == 0
      assert tile.series == List.duplicate(0, 24)
    end
  end

  describe "cycle_tile/2" do
    test "averages each leg over the tickets merged in the window" do
      cycles = [
        %{issue_at: at(3000), pr_at: at(2400), merged_at: at(600)},
        %{issue_at: at(5000), pr_at: at(4800), merged_at: at(1200)},
        %{issue_at: nil, pr_at: at(2 * 86_400 + 600), merged_at: at(2 * 86_400)},
        %{issue_at: at(100), pr_at: at(50), merged_at: nil}
      ]

      tile = Metrics.cycle_tile(cycles, @now)

      assert tile.day == %{n: 2, issue_to_pr: 400, pr_to_merge: 2700}
      assert tile.week == %{n: 3, issue_to_pr: 400, pr_to_merge: 2000}
    end

    test "no cycles is a count of zero with no means" do
      assert Metrics.cycle_tile([], @now).day == %{n: 0, issue_to_pr: nil, pr_to_merge: nil}
    end
  end

  describe "load_tile/1" do
    test "measured and unknown" do
      assert %{status: :measured, running: 1, max: 3, queued: 0} =
               Metrics.load_tile({:ok, %{running: 1, queued: 0, max_workers: 3}})

      assert %{status: :unknown, reason: :unreachable, running: nil} =
               Metrics.load_tile({:error, :unreachable})
    end
  end

  describe "throughput/3" do
    test "assembles the tiles in display order" do
      flow = Metrics.throughput(%{done: {:ok, []}, load: {:error, :not_configured}}, @now, 180)

      assert Enum.map(flow.tiles, & &1.key) ==
               ~w(done opened merged commits tickets queue cycle load)

      assert flow.computed_at == @now
      assert length(flow.buckets) == 24

      statuses = Map.new(flow.tiles, &{&1.key, &1.status})
      assert statuses["done"] == :measured
      assert statuses["opened"] == :unknown
      assert statuses["load"] == :unknown
    end
  end

  describe "words" do
    setup do
      Gettext.put_locale(AgentBoardWeb.Gettext, "pt_BR")
      :ok
    end

    test "the English board writes the rate and the reason its way" do
      Gettext.put_locale(AgentBoardWeb.Gettext, "en")

      assert Metrics.rate(1.66) == "1.7"
      assert Metrics.reason(:unreachable) == "orchestrator unreachable"
      assert Metrics.reason({:http, 503}) == "orchestrator returned HTTP 503"
    end

    test "counts, rates, deltas and durations" do
      assert Metrics.count(nil) == "?"
      assert Metrics.count(12) == "12"
      assert Metrics.rate(nil) == "—"
      assert Metrics.rate(1.66) == "1,7"
      assert Metrics.rate(0) == "0,0"
      assert Metrics.delta(nil) == "—"
      assert Metrics.delta(0) == "="
      assert Metrics.delta(2) == "+2"
      assert Metrics.delta(-1) == "−1"
      assert Metrics.duration(nil) == "—"
      assert Metrics.duration(42) == "42 s"
      assert Metrics.duration(720) == "12 min"
      assert Metrics.duration(3900) == "1 h 05 min"
      assert Metrics.duration(2 * 86_400 + 3 * 3600 + 7) == "2 d 3 h"
      assert Metrics.reason(:never_synced) == "ainda sem leitura dos commits"
      assert Metrics.reason({:http, 503}) == "orquestrador respondeu HTTP 503"
    end
  end
end
