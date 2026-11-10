defmodule AgentBoardWeb.BoardComponents.MergeTrend do
  @moduledoc "A seven-day view of dated merges in the already loaded history."
  use AgentBoardWeb, :live_component

  @impl true
  def render(assigns) do
    today = Date.utc_today()
    dates = Enum.map(6..0//-1, &Date.add(today, -&1))

    counts =
      assigns.items
      |> Enum.filter(&match?(%DateTime{}, &1.merged_at))
      |> Enum.frequencies_by(&DateTime.to_date(&1.merged_at))

    # With older pages still unread, the oldest loaded day is a minimum and
    # the days before it were never counted: neither is a zero.
    oldest = if assigns[:has_more], do: counts |> Map.keys() |> Enum.min(Date, fn -> nil end)

    peak = dates |> Enum.map(&Map.get(counts, &1, 0)) |> Enum.max() |> max(1)

    days =
      Enum.map(dates, fn date ->
        count = Map.get(counts, date, 0)

        known =
          cond do
            is_nil(oldest) -> :exact
            Date.compare(date, oldest) == :lt -> :unread
            date == oldest -> :minimum
            true -> :exact
          end

        %{date: date, count: count, known: known, height: round(count * 100 / peak)}
      end)

    assigns =
      assigns
      |> assign(:days, days)
      |> assign(:partial, Enum.any?(days, &(&1.known != :exact)))
      |> assign(:recent_count, Enum.sum(Enum.map(days, & &1.count)))

    ~H"""
    <figure id={@id} class="merge-trend">
      <figcaption>
        <strong>{gettext("Recent merges")}</strong>
        <span>
          {gettext("%{count} in the last 7 UTC days · loaded history",
            count: if(@partial, do: "≥ #{@recent_count}", else: @recent_count)
          )}
        </span>
      </figcaption>
      <ol aria-label={gettext("Loaded merges per UTC day")}>
        <li :for={day <- @days} aria-label={day_label(day)}>
          <span class="merge-trend-count">{day_count(day)}</span>
          <span class="merge-trend-track">
            <span class="merge-trend-bar" style={"height: #{day.height}%"}></span>
          </span>
          <time datetime={day.date}>{Calendar.strftime(day.date, "%d %b")}</time>
        </li>
      </ol>
    </figure>
    """
  end

  defp day_count(%{known: :unread}), do: "?"
  defp day_count(%{known: :minimum, count: count}), do: "≥#{count}"
  defp day_count(%{count: count}), do: count

  defp day_label(%{known: :unread, date: date}),
    do: gettext("%{date}: not loaded yet; scroll the list to load it", date: date)

  defp day_label(%{known: :minimum, date: date, count: count}),
    do: gettext("%{date}: at least %{count} loaded merges", date: date, count: count)

  defp day_label(%{date: date, count: count}),
    do: gettext("%{date}: %{count} loaded merges", date: date, count: count)
end
