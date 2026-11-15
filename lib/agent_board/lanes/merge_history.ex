defmodule AgentBoard.Lanes.MergeHistory do
  @moduledoc "Calendar and counting rules for the board’s merge history."

  alias AgentBoard.Time

  @days 7

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
end
