defmodule AgentBoard.Lanes.MergeHistory do
  @moduledoc "Calendar and counting rules for the board’s merge history."

  alias AgentBoard.Lanes.CI
  alias AgentBoard.Time

  @days 7
  @compact 3
  @wide 8

  @doc "The seven local dates shown in the log and the UTC instant that starts the first date."
  @spec window(DateTime.t(), integer()) :: %{
          today: Date.t(),
          dates: Date.Range.t(),
          since: DateTime.t()
        }
  def window(now, offset) do
    today = Time.local_date(now, offset)
    first = Date.add(today, 1 - @days)
    since = DateTime.new!(first, ~T[00:00:00Z]) |> DateTime.add(offset * 60, :second)
    %{today: today, dates: Date.range(first, today), since: since}
  end

  @doc "Count distinct issues closed by the supplied merges, across one day or the whole window."
  @spec delivered([map()]) :: non_neg_integer()
  def delivered(pulls),
    do: pulls |> Enum.flat_map(&(&1.closes_issues || [])) |> Enum.uniq() |> length()

  @doc "Count all merges and issues, but only local pass/fail evidence for the daily CI dots."
  @spec day_totals([map()], map()) :: map()
  def day_totals(pulls, local_ci) do
    results = Enum.frequencies_by(pulls, &CI.local_result(local_ci[&1.number]))

    %{
      n: length(pulls),
      issues: delivered(pulls),
      ok: Map.get(results, :pass, 0),
      fail: Map.get(results, :fail, 0)
    }
  end

  @doc "Keep the first three merges in the compact view and up to eight in the wide view, in input order."
  @spec day_page([term()]) :: map()
  def day_page(pulls) do
    {items, rest} = Enum.split(pulls, @compact)
    {extra, hidden} = Enum.split(rest, @wide - @compact)
    more_wide = length(hidden)
    %{items: items, extra: extra, more: length(extra) + more_wide, more_wide: more_wide}
  end
end
