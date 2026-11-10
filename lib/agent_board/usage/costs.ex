defmodule AgentBoard.Usage.Costs do
  @moduledoc """
  What a usage-ledger row costs, in the currency its executor spends.

  Three currencies, never added together (`docs/research/alfred.md`, 3.3):

    * the harness (`dsh`) spends DeepSeek balance: US$ estimated from the
      board's price table (`AgentBoard.AI.Providers`). The table has no cache
      price, so a row with cache tokens makes the total a minimum (`≥`), and
      a model without a price makes it unknown;
    * Claude Code runs on the owner's Claude Max subscription. Its US$ is a
      list-price reference, estimated from the tokens and the per-model
      prices Claude Code itself reports in its `cost-state` lines (observed
      on 2026-11-07). It is not a bill, and the real cost is a quota the
      files do not hold: the quota is unknown until a reader exists;
    * Codex runs on the ChatGPT plan and has no US$ anywhere. Its currency is
      the share of the weekly window, read from `usage_limits`.

  A missing price is `nil`, never zero. `cost/2` returns `nil` for an unknown
  model and `complete?: false` for a total that is only a minimum.
  """

  alias AgentBoard.AI.Providers

  @type cost :: %{micros: non_neg_integer(), complete?: boolean(), currency: :usd}
  @type row :: %{
          optional(:model) => String.t() | nil,
          optional(:input_tokens) => non_neg_integer(),
          optional(:output_tokens) => non_neg_integer(),
          optional(:cache_read_tokens) => non_neg_integer(),
          optional(:cache_write_tokens) => non_neg_integer(),
          optional(:cache_write_1h_tokens) => non_neg_integer()
        }

  # Claude Code's own list price per million tokens, in US$: input and output
  # read from the `modelUsage` entries of its `cost-state` lines (observed
  # 2026-11-07) by least squares with the cache ratios below. A family whose
  # samples did not separate the rates uses the family's main model; a model
  # absent here is unpriced, not free. opus-4-8, fable-5-2 and haiku-5-5 were
  # read on 2026-11-10 from lines that split 5-minute and 1-hour cache writes,
  # where the price is exact. The opus-4-8 lines are of sessions started from
  # 2026-10-02 to 2026-11-07: its older rows use the same rate unverified.
  # Haiku's web searches (US$ 0.01 each there) are not in the ledger, so a
  # haiku row is a minimum.
  @claude_prices %{
    "claude-opus-5-5" => %{input: 2.30, output: 30.00},
    "claude-opus-5-5[1m]" => %{input: 2.30, output: 30.00},
    "claude-opus-5" => %{input: 2.30, output: 30.00},
    "claude-opus-4-8" => %{input: 5.00, output: 25.00},
    "claude-sonnet-5-5" => %{input: 1.62, output: 12.73},
    "claude-sonnet-5" => %{input: 1.62, output: 12.73},
    "claude-fable-5-1" => %{input: 5.29, output: 42.57},
    "claude-fable-5" => %{input: 5.29, output: 42.57},
    "claude-fable-5-2" => %{input: 5.00, output: 25.00},
    "claude-haiku-5-5" => %{input: 0.10, output: 0.50}
  }

  # Anthropic's cache multipliers over the input price: a read costs 10 % of
  # the input, a 5-minute write 125 % and a 1-hour write 200 %. A row read
  # before the ledger told the two writes apart holds no 1-hour count and is
  # priced at the 5-minute rate, a minimum, until its file is read again.
  @cache_read_multiplier 0.10
  @no_peak %{input: 0, output: 0, cache_read: 0}
  @cache_write_multiplier 1.25
  @cache_write_1h_multiplier 2.00

  @doc "The sources whose cost/2 is in US$."
  def usd_sources, do: ["dsh", "claude_code"]

  @doc """
  The price per million tokens for a source and model, or nil when the board
  has no price. `complete?` is false when a token kind has no price.
  """
  @spec prices(String.t(), String.t() | nil) ::
          %{
            optional(:cache_write_1h) => number(),
            optional(:off_peak) => number() | nil,
            input: number(),
            output: number(),
            cache_read: number() | nil,
            cache_write: number() | nil
          }
          | nil
  def prices("dsh", model) do
    case Providers.prices_for_model(model) do
      nil ->
        nil

      prices ->
        %{
          input: Map.get(prices, :input, 0),
          output: Map.get(prices, :output, 0),
          cache_read: Map.get(prices, :cache_read),
          cache_write: Map.get(prices, :cache_write),
          off_peak: Map.get(prices, :off_peak)
        }
    end
  end

  def prices("claude_code", model) when is_binary(model) do
    case Map.get(@claude_prices, model) do
      nil ->
        nil

      %{input: input, output: output} ->
        %{
          input: input,
          output: output,
          cache_read: input * @cache_read_multiplier,
          cache_write: input * @cache_write_multiplier,
          cache_write_1h: input * @cache_write_1h_multiplier
        }
    end
  end

  def prices(_source, _model), do: nil

  @doc """
  The cost of these ledger rows (all from one source), in microdollars. Rows
  with an unpriced model are left out and make the total a minimum; nil when
  no row can be priced at all. An empty list is a measured zero.
  """
  @spec cost(String.t(), [row()]) :: cost() | nil
  def cost(source, rows) when source in ["dsh", "claude_code"] do
    {micros, priced?, complete?} =
      Enum.reduce(rows, {0, false, true}, fn row, {micros, priced?, complete?} ->
        case row_cost(source, row) do
          nil ->
            {micros, priced?, false}

          {value, row_complete?} ->
            {micros + value, true, complete? and row_complete?}
        end
      end)

    if priced?,
      do: %{micros: micros, complete?: complete?, currency: :usd},
      else: nil
  end

  def cost(_source, _rows), do: nil

  defp row_cost(source, row) do
    case prices(source, row[:model]) do
      %{} = prices -> priced_row(row, prices)
      _ -> nil
    end
  end

  defp priced_row(row, prices) do
    input = count(row[:input_tokens])
    output = count(row[:output_tokens])
    cache_read = count(row[:cache_read_tokens])
    cache_write = count(row[:cache_write_tokens])
    one_hour = one_hour_writes(row, prices, cache_write)
    {peak, timed?} = peak_tokens(row, prices)

    complete? =
      timed? and (cache_read == 0 or prices.cache_read != nil) and
        (cache_write == 0 or prices.cache_write != nil)

    micros =
      round(
        Providers.at_full_rate(input, peak.input, prices) * prices.input +
          Providers.at_full_rate(output, peak.output, prices) * prices.output +
          Providers.at_full_rate(cache_read, peak.cache_read, prices) *
            (prices.cache_read || 0) +
          (cache_write - one_hour) * (prices.cache_write || 0) +
          one_hour * (prices[:cache_write_1h] || 0)
      )

    {micros, complete?}
  end

  # Which tokens paid the peak rate, and whether the row can say. A price with
  # one rate needs no hour. A ledger row covers a whole day: `Report.rows/2`
  # gives it the split (`:peak`); a single message has its instant (`:at`). A
  # row with neither is priced off-peak and is a minimum.
  defp peak_tokens(row, prices) do
    cond do
      is_nil(prices[:off_peak]) -> {@no_peak, true}
      is_map(row[:peak]) -> {row.peak, true}
      is_struct(row[:at], DateTime) -> {message_peak(row), true}
      true -> {@no_peak, false}
    end
  end

  defp message_peak(row) do
    if Providers.peak?(row.at) do
      %{
        input: count(row[:input_tokens]),
        output: count(row[:output_tokens]),
        cache_read: count(row[:cache_read_tokens])
      }
    else
      @no_peak
    end
  end

  # The 1-hour part of the write, for a source with a rate for it.
  defp one_hour_writes(row, %{cache_write_1h: _rate}, cache_write),
    do: min(count(row[:cache_write_1h_tokens]), cache_write)

  defp one_hour_writes(_row, _prices, _cache_write), do: 0

  defp count(n) when is_integer(n) and n > 0, do: n
  defp count(_), do: 0

  @doc """
  The share of the weekly Codex window in the newest reading: the widest
  window of at least a week (`10080` minutes) that has not reset yet. nil
  when there is no such reading, never zero.
  """
  @spec codex_weekly([map()]) ::
          %{
            used_percent: float(),
            window_minutes: integer(),
            resets_at: DateTime.t() | nil,
            observed_at: DateTime.t() | nil
          }
          | nil
  def codex_weekly(limits) do
    limits
    |> Enum.filter(&(&1[:source] == "codex"))
    |> Enum.flat_map(&windows/1)
    |> Enum.filter(&(&1.window_minutes >= 10_080 and not reset?(&1.resets_at)))
    |> Enum.max_by(
      &{&1.window_minutes, DateTime.to_unix(&1.observed_at, :microsecond)},
      fn -> nil end
    )
  end

  # A reading from before the reset says nothing about the current week.
  defp reset?(%DateTime{} = resets_at), do: DateTime.compare(resets_at, DateTime.utc_now()) == :lt
  defp reset?(_resets_at), do: false

  defp windows(limit) do
    [
      %{
        used_percent: limit[:primary_used_percent],
        window_minutes: limit[:primary_window_minutes],
        resets_at: limit[:primary_resets_at],
        observed_at: limit[:observed_at]
      },
      %{
        used_percent: limit[:secondary_used_percent],
        window_minutes: limit[:secondary_window_minutes],
        resets_at: limit[:secondary_resets_at],
        observed_at: limit[:observed_at]
      }
    ]
    |> Enum.filter(&(is_number(&1.used_percent) and is_integer(&1.window_minutes)))
  end
end
