defmodule AgentBoardWeb.Time do
  @moduledoc "The board's times and dates; `AgentBoard.Time` words them in the reader's language."

  alias AgentBoard.Time, as: BoardTime

  defdelegate age_seconds(at, now), to: BoardTime
  defdelegate duration(seconds), to: BoardTime
  defdelegate local(at, offset), to: BoardTime
  defdelegate local_time(at, offset), to: BoardTime
  defdelegate local_date(at, offset), to: BoardTime
  defdelegate ago(seconds), to: BoardTime
  defdelegate age_or_seen(seconds, frozen, at, offset), to: BoardTime
  defdelegate frozen_count(n, frozen), to: BoardTime
  defdelegate since_label(at, offset, now), to: BoardTime
  defdelegate day_label(date, today), to: BoardTime
  defdelegate short_day_label(date, today), to: BoardTime
  defdelegate weekday(date), to: BoardTime
  defdelegate month(date), to: BoardTime
end
