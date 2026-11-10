defmodule AgentBoard.Time do
  @moduledoc """
  Presentation of time for the board: relative for what is recent, absolute
  for the record, always in the reader's offset (minutes west of UTC, as the
  browser reports it).
  """

  use Gettext, backend: AgentBoardWeb.Gettext

  @doc "Whole seconds between `at` and `now`; never negative."
  def age_seconds(nil, _now), do: nil

  def age_seconds(%DateTime{} = at, %DateTime{} = now) do
    max(DateTime.diff(now, at, :second), 0)
  end

  @doc "A relative phrase in the board's voice."
  def ago(nil), do: gettext("unknown")
  def ago(sec) when sec < 60, do: gettext("%{count} s ago", count: sec)
  def ago(sec) when sec < 3600, do: gettext("%{count} min ago", count: div(sec, 60))
  def ago(sec) when sec < 86_400, do: gettext("%{count} h ago", count: div(sec, 3600))
  def ago(sec), do: gettext("%{count} d ago", count: div(sec, 86_400))

  @doc "Elapsed time for a running task: m:ss, or h mm min past an hour."
  def duration(nil), do: "—"
  def duration(sec) when sec < 0, do: "0:00"

  def duration(sec) do
    h = div(sec, 3600)
    m = div(rem(sec, 3600), 60)
    s = rem(sec, 60)

    if h > 0,
      do: "#{h} h #{String.pad_leading("#{m}", 2, "0")} min",
      else: "#{m}:#{String.pad_leading("#{s}", 2, "0")}"
  end

  @doc "UTC to the reader's local DateTime; offset is minutes west of UTC."
  def local(%DateTime{} = at, offset) when is_integer(offset),
    do: DateTime.add(at, -offset * 60, :second)

  def local_time(nil, _offset), do: "—"

  def local_time(%DateTime{} = at, offset) do
    local(at, offset) |> DateTime.to_time() |> Time.to_string() |> String.slice(0, 5)
  end

  def local_date(%DateTime{} = at, offset), do: local(at, offset) |> DateTime.to_date()

  @doc "today at 22:10, yesterday at 22:10 or Tuesday, Nov 4 at 22:10."
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

  @doc "The group heading: Today, Yesterday, 5 Nov or Tuesday, 4 Nov."
  def day_label(date, today) do
    cond do
      date == today ->
        gettext("Today")

      date == Date.add(today, -1) ->
        gettext("Yesterday, %{date} %{month}", date: date.day, month: month(date))

      true ->
        # Portuguese writes the weekday in lower case; a heading starts with a capital.
        gettext("%{day}, %{date} %{month}",
          day: String.capitalize(weekday(date)),
          date: date.day,
          month: month(date)
        )
    end
  end

  @doc "Short label under the week dots."
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
