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

    peak = dates |> Enum.map(&Map.get(counts, &1, 0)) |> Enum.max() |> max(1)

    days =
      Enum.map(dates, fn date ->
        count = Map.get(counts, date, 0)
        %{date: date, count: count, height: round(count * 100 / peak)}
      end)

    assigns =
      assigns
      |> assign(:days, days)
      |> assign(:recent_count, Enum.sum(Enum.map(days, & &1.count)))

    ~H"""
    <figure id={@id} class="merge-trend">
      <figcaption>
        <strong>Mesclagens recentes</strong>
        <span>{@recent_count} nos últimos 7 dias UTC · histórico carregado</span>
      </figcaption>
      <ol aria-label="Mesclagens carregadas por dia UTC">
        <li :for={day <- @days} aria-label={"#{day.date}: #{day.count} mesclagens carregadas"}>
          <span class="merge-trend-count">{day.count}</span>
          <span class="merge-trend-track">
            <span class="merge-trend-bar" style={"height: #{day.height}%"}></span>
          </span>
          <time datetime={day.date}>{Calendar.strftime(day.date, "%d %b")}</time>
        </li>
      </ol>
    </figure>
    """
  end
end
