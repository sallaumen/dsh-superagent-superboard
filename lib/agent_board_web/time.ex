defmodule AgentBoardWeb.Time do
  @moduledoc "Locale-aware presentation of board times and dates."

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Time, as: BoardTime

  defdelegate age_seconds(at, now), to: BoardTime
  defdelegate duration(seconds), to: BoardTime
  defdelegate local(at, offset), to: BoardTime
  defdelegate local_time(at, offset), to: BoardTime
  defdelegate local_date(at, offset), to: BoardTime

  def ago(nil), do: gettext("unknown")
  def ago(seconds) when seconds < 60, do: gettext("%{count} s ago", count: seconds)
  def ago(seconds) when seconds < 3600, do: gettext("%{count} min ago", count: div(seconds, 60))
  def ago(seconds) when seconds < 86_400, do: gettext("%{count} h ago", count: div(seconds, 3600))
  def ago(seconds), do: gettext("%{count} d ago", count: div(seconds, 86_400))

  def since_label(nil, _offset, _now), do: gettext("before your last visit")

  def since_label(%DateTime{} = at, offset, now) do
    date = local_date(at, offset)
    today = local_date(now, offset)
    time = local_time(at, offset)

    cond do
      date == today ->
        gettext("today at %{time}", time: time)

      date == Date.add(today, -1) ->
        gettext("yesterday at %{time}", time: time)

      true ->
        gettext("%{day}, %{date} %{month} at %{time}",
          day: weekday(date),
          date: date.day,
          month: month(date),
          time: time
        )
    end
  end

  def day_label(date, today) do
    cond do
      date == today ->
        gettext("Today")

      date == Date.add(today, -1) ->
        gettext("Yesterday, %{date} %{month}", date: date.day, month: month(date))

      true ->
        gettext("%{day}, %{date} %{month}",
          day: String.capitalize(weekday(date)),
          date: date.day,
          month: month(date)
        )
    end
  end

  def short_day_label(date, today) do
    if date == today, do: gettext("today"), else: String.pad_leading("#{date.day}", 2, "0")
  end

  def weekday(%Date{} = date) do
    case Date.day_of_week(date) do
      1 -> gettext("Monday")
      2 -> gettext("Tuesday")
      3 -> gettext("Wednesday")
      4 -> gettext("Thursday")
      5 -> gettext("Friday")
      6 -> gettext("Saturday")
      7 -> gettext("Sunday")
    end
  end

  def month(%Date{month: month}) do
    Enum.at(
      [
        gettext("Jan"),
        gettext("Feb"),
        gettext("Mar"),
        gettext("Apr"),
        gettext("May"),
        gettext("Jun"),
        gettext("Jul"),
        gettext("Aug"),
        gettext("Sep"),
        gettext("Oct"),
        gettext("Nov"),
        gettext("Dec")
      ],
      month - 1
    )
  end
end
