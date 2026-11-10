defmodule AgentBoard.Metrics do
  @moduledoc """
  The throughput block's arithmetic, pure: counts per hour from observed
  timestamps, a queue depth from queued spans, mean cycle times and the
  runner's load. What was not observed is `:unknown`, never zero.

  Every window is a sliding one ending at `now`: the last 60 minutes, the last
  24 hours and the last 7 days. The sparkline is different on purpose: 24
  clock hours in the reader's offset (23 full ones and the current, partial
  one), so a bar is "14:00–15:00" and the shape reads like a clock.
  """

  use Gettext, backend: AgentBoardWeb.Gettext

  @hour 3600
  @day 86_400
  @week 7 * @day
  @hours_per_day 24
  @hours_per_week 168

  @typedoc "Observed timestamps, or the reason they are not known."
  @type observation :: {:ok, [DateTime.t()]} | {:unknown, term()}

  @typedoc "One clock hour: `from` inclusive, `to` exclusive (inclusive for the current hour)."
  @type bucket :: %{from: DateTime.t(), to: DateTime.t()}

  @doc """
  The rate tiles, in display order: the key, the label and the observation
  the tile counts. Documented, with each source, in docs/maintainer-contract.md.
  """
  def rate_keys,
    do: [
      {"done", "Concluídas", :done},
      {"opened", "Issues abertas", :opened},
      {"merged", "PRs mesclados", :merged},
      {"commits", "Commits", :commits},
      {"tickets", "Tickets encerrados", :tickets}
    ]

  @doc """
  The whole block from the observations (`AgentBoard.Metrics.Observations.read/3`).

  `offset` is the reader's offset in minutes west of UTC, as the browser
  reports it; it aligns the sparkline's clock hours.
  """
  @spec throughput(map(), DateTime.t(), integer()) :: map()
  def throughput(observations, %DateTime{} = now, offset) when is_integer(offset) do
    buckets = hour_buckets(now, offset)

    rates =
      Enum.map(rate_keys(), fn {key, label, field} ->
        rate_tile(key, label, Map.get(observations, field, {:unknown, :missing}), now, buckets)
      end)

    %{
      computed_at: now,
      offset: offset,
      buckets: buckets,
      tiles:
        rates ++
          [
            queue_tile(Map.get(observations, :queue, []), now, offset, buckets),
            cycle_tile(Map.get(observations, :cycles, []), now),
            load_tile(Map.get(observations, :load, {:error, :missing}))
          ]
    }
  end

  @doc """
  The last `count` clock hours in the reader's offset, oldest first. Every
  bucket but the last is a full hour; the last runs from the top of the
  current hour to `now`.
  """
  @spec hour_buckets(DateTime.t(), integer(), pos_integer()) :: [bucket()]
  def hour_buckets(%DateTime{} = now, offset, count \\ @hours_per_day) do
    current = hour_floor(now, offset)

    for i <- (count - 1)..0//-1 do
      from = DateTime.add(current, -i * @hour, :second)
      to = if i == 0, do: now, else: DateTime.add(from, @hour, :second)
      %{from: from, to: to}
    end
  end

  # The top of the reader's current hour, as a UTC instant. Shifting by the
  # offset, flooring and shifting back keeps a half-hour zone (offset -330)
  # on its own :30 boundary.
  defp hour_floor(now, offset) do
    local = DateTime.add(now, -offset * 60, :second)
    floored = %{local | minute: 0, second: 0, microsecond: {0, 0}}
    DateTime.add(floored, offset * 60, :second)
  end

  @doc "How many timestamps fall in each bucket."
  @spec series([DateTime.t()], [bucket()]) :: [non_neg_integer()]
  def series(timestamps, buckets) do
    last = length(buckets) - 1

    buckets
    |> Enum.with_index()
    |> Enum.map(fn {bucket, index} ->
      Enum.count(timestamps, &inside?(&1, bucket, index == last))
    end)
  end

  defp inside?(at, %{from: from, to: to}, inclusive?) do
    DateTime.compare(at, from) != :lt and
      (DateTime.compare(at, to) == :lt or (inclusive? and DateTime.compare(at, to) == :eq))
  end

  @doc """
  How many timestamps fall in the `seconds` before `now` (exclusive at the
  start, inclusive at `now`), shifted `back` seconds into the past.
  """
  @spec within([DateTime.t()], DateTime.t(), pos_integer(), non_neg_integer()) ::
          non_neg_integer()
  def within(timestamps, %DateTime{} = now, seconds, back \\ 0) do
    to = DateTime.add(now, -back, :second)
    from = DateTime.add(to, -seconds, :second)

    Enum.count(timestamps, fn at ->
      DateTime.compare(at, from) == :gt and DateTime.compare(at, to) != :gt
    end)
  end

  @doc "A rate tile: the last hour, the hour before, 24 h, 7 d and the sparkline."
  def rate_tile(key, label, {:ok, timestamps}, now, buckets) do
    hour = within(timestamps, now, @hour)
    previous = within(timestamps, now, @hour, @hour)
    day = within(timestamps, now, @day)
    week = within(timestamps, now, @week)

    %{
      key: key,
      label: label,
      kind: :rate,
      status: :measured,
      reason: nil,
      hour: hour,
      previous: previous,
      delta: hour - previous,
      day: day,
      week: week,
      day_rate: day / @hours_per_day,
      week_rate: week / @hours_per_week,
      series: series(timestamps, buckets)
    }
  end

  def rate_tile(key, label, {:unknown, reason}, _now, _buckets) do
    %{
      key: key,
      label: label,
      kind: :rate,
      status: :unknown,
      reason: reason,
      hour: nil,
      previous: nil,
      delta: nil,
      day: nil,
      week: nil,
      day_rate: nil,
      week_rate: nil,
      series: nil
    }
  end

  @doc """
  How many spans were open at `at`: `from <= at` and the span has not ended
  (`to` is nil or after `at`).
  """
  @spec depth_at([{DateTime.t(), DateTime.t() | nil}], DateTime.t()) :: non_neg_integer()
  def depth_at(spans, %DateTime{} = at) do
    Enum.count(spans, fn {from, to} ->
      DateTime.compare(from, at) != :gt and (is_nil(to) or DateTime.compare(to, at) == :gt)
    end)
  end

  @doc "The queue tile: the depth now, an hour ago, at each hour's end, and the peaks."
  def queue_tile(spans, now, offset, buckets) do
    depths = Enum.map(buckets, &depth_at(spans, &1.to))
    week = hour_buckets(now, offset, @hours_per_week) |> Enum.map(&depth_at(spans, &1.to))
    hour = depth_at(spans, now)
    previous = depth_at(spans, DateTime.add(now, -@hour, :second))

    %{
      key: "queue",
      label: "Fila",
      kind: :depth,
      status: :measured,
      reason: nil,
      hour: hour,
      previous: previous,
      delta: hour - previous,
      day: Enum.max(depths, fn -> 0 end),
      week: Enum.max(week, fn -> 0 end),
      series: depths
    }
  end

  @doc """
  The cycle tile: mean issue → PR and PR → merge over the tickets whose PR
  merged in the window. A cycle is `%{issue_at, pr_at, merged_at}`; a missing
  leg is left out of that mean, never counted as zero.
  """
  def cycle_tile(cycles, now) do
    %{
      key: "cycle",
      label: "Ciclo",
      kind: :cycle,
      status: :measured,
      reason: nil,
      day: cycle_window(cycles, now, @day),
      week: cycle_window(cycles, now, @week)
    }
  end

  defp cycle_window(cycles, now, seconds) do
    merged =
      Enum.filter(cycles, fn cycle ->
        match?(%DateTime{}, cycle[:merged_at]) and within([cycle.merged_at], now, seconds) == 1
      end)

    %{
      n: length(merged),
      issue_to_pr: mean_seconds(merged, :issue_at, :pr_at),
      pr_to_merge: mean_seconds(merged, :pr_at, :merged_at)
    }
  end

  @doc "The mean of `to - from` in whole seconds over the entries that have both; nil for none."
  def mean_seconds(entries, from_key, to_key) do
    durations =
      for entry <- entries,
          %DateTime{} = from <- [entry[from_key]],
          %DateTime{} = to <- [entry[to_key]],
          seconds = DateTime.diff(to, from, :second),
          seconds >= 0,
          do: seconds

    case durations do
      [] -> nil
      list -> div(Enum.sum(list), length(list))
    end
  end

  @doc "The load tile: running workers out of the ceiling, and the runner's own queue."
  def load_tile({:ok, %{running: running, queued: queued, max_workers: max}}) do
    %{
      key: "load",
      label: "Paralelismo",
      kind: :load,
      status: :measured,
      reason: nil,
      running: running,
      queued: queued,
      max: max
    }
  end

  def load_tile({:error, reason}) do
    %{
      key: "load",
      label: "Paralelismo",
      kind: :load,
      status: :unknown,
      reason: reason,
      running: nil,
      queued: nil,
      max: nil
    }
  end

  # -- presentation helpers (pure, so the component stays markup) -----------

  @doc "A count, or `?` for what was not observed."
  def count(nil), do: "?"
  def count(n) when is_integer(n), do: Integer.to_string(n)

  @doc "A per-hour rate with one decimal and the viewer's decimal mark: 1,7 or 1.7."
  def rate(nil), do: "—"

  def rate(value) when is_number(value),
    do: (value / 1) |> Float.round(1) |> AgentBoardWeb.Numbers.decimal(1)

  @doc "The change against the previous hour: +2, −1 or = for no change."
  def delta(nil), do: "—"
  def delta(0), do: "="
  def delta(n) when n > 0, do: "+#{n}"
  def delta(n) when n < 0, do: "−#{-n}"

  @doc "A duration in the board's voice: 42 s, 12 min, 1 h 05 min, 2 d 3 h."
  def duration(nil), do: "—"
  def duration(sec) when sec < 60, do: "#{sec} s"
  def duration(sec) when sec < @hour, do: "#{div(sec, 60)} min"

  def duration(sec) when sec < @day do
    "#{div(sec, @hour)} h #{String.pad_leading("#{div(rem(sec, @hour), 60)}", 2, "0")} min"
  end

  def duration(sec), do: "#{div(sec, @day)} d #{div(rem(sec, @day), @hour)} h"

  @doc "Why a value is unknown, in words."
  def reason(:never_synced), do: gettext("no commit reading yet")
  def reason(:not_configured), do: gettext("orchestrator not configured")
  def reason(:unreachable), do: gettext("orchestrator unreachable")
  def reason(:malformed), do: gettext("orchestrator response lacks load")
  def reason({:http, status}), do: gettext("orchestrator returned HTTP %{status}", status: status)
  def reason(:agent_unavailable), do: gettext("agent status unavailable")
  def reason(_other), do: gettext("no observed data")
end
