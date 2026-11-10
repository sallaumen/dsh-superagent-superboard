defmodule AgentBoardWeb.BoardComponents.Today do
  @moduledoc """
  The Today view combines decisions and work across tracked repositories,
  a persisted summary, weekly results, and usage by source. It reads prepared
  snapshots from the board load; incoming data does not animate.
  """
  use AgentBoardWeb, :html

  alias AgentBoardWeb.Time
  import AgentBoardWeb.Components.VersionBadge, only: [version_badge: 1]
  import AgentBoardWeb.BoardComponents.DailySummary, only: [daily_summary: 1]

  @sources ["dsh", "claude_code", "codex"]
  @labels %{"dsh" => "DeepSeek", "claude_code" => "Claude Code", "codex" => "Codex"}

  attr :today, :map, required: true
  attr :spend, :map, default: nil
  attr :offset, :integer, default: 0
  attr :now, :any, default: nil
  attr :version, :map, default: %{state: :unknown}
  attr :daily_summary, :map, default: nil

  def today_view(assigns) do
    now = assigns.now || DateTime.utc_now()

    assigns =
      assigns
      |> assign(:now, now)
      |> assign(:spend_rows, spend_rows(assigns.spend))
      |> assign(:date_label, date_label(now, assigns.offset))
      |> assign(:projects, Map.get(assigns.today, :projects, []))
      |> assign(:trend, trend_bars(Map.get(assigns.today, :trend, [])))
      |> assign(:trend_total, Enum.sum(Enum.map(Map.get(assigns.today, :trend, []), & &1.count)))
      |> assign(:merged_today, Map.get(assigns.today, :merged_today, 0))
      |> assign(:delivered_today, Map.get(assigns.today, :delivered_today, 0))
      |> assign(:seen_today, Map.get(assigns.today, :seen_today, 0))
      |> assign(:queued, length(Map.get(assigns.today, :queue, [])))

    ~H"""
    <section id="today" class="ab-today" aria-labelledby="today-title">
      <header class="ab-today__head">
        <div class="ab-today__title-row">
          <h1 id="today-title">{gettext("Today")}</h1>
          <span class="ab-today__date">{@date_label}</span>
          <.version_badge version={@version} />
        </div>
        <p class="ab-meta ab-today__scope">
          {gettext("All tracked projects · data recorded by the board")}
        </p>
      </header>

      <section id="today-overview" class="ab-today__overview" aria-label={gettext("Today so far")}>
        <div class="ab-today__metric">
          <span class="ab-label">{gettext("Issues delivered today")}</span>
          <strong>{@delivered_today}</strong>
          <span class="ab-meta">{gettext("closed by a merged PR")}</span>
        </div>
        <div class="ab-today__metric">
          <span class="ab-label">{gettext("PRs merged today")}</span>
          <strong>{@merged_today}</strong>
          <span class="ab-meta">{gettext("recorded by the board")}</span>
        </div>
        <div class="ab-today__metric">
          <span class="ab-label">{gettext("Issues seen today")}</span>
          <strong>{@seen_today}</strong>
          <span class="ab-meta">{gettext("first seen by the board")}</span>
        </div>
        <div class="ab-today__metric">
          <span class="ab-label">{gettext("Queued now")}</span>
          <strong>{@queued}</strong>
          <span class="ab-meta">{gettext("across all projects")}</span>
        </div>
      </section>

      <div class={["ab-today__work", @daily_summary && "ab-today__work--with-report"]}>
        <div class="ab-today__worklists">
          <section id="today-needs" class="ab-today__section" aria-labelledby="today-needs-title">
            <div class="ab-sec__head">
              <h2 id="today-needs-title">{gettext("Needs you")}</h2>
              <span class="ab-sec__count">{length(@today.needs)}</span>
            </div>

            <p :if={@today.needs == []} class="ab-sec__empty">
              {gettext("Nothing waiting for you in the board repositories.")}
            </p>

            <ol :if={@today.needs != []} class="ab-today__list">
              <li :for={item <- @today.needs}>
                <button
                  type="button"
                  class="ab-today__item"
                  phx-click="open_any"
                  phx-value-id={item.id}
                >
                  <span class="ab-today__repo">{item.repo}</span>
                  <span class="ab-today__num">#{item.number}</span>
                  <span class="ab-today__title">{item.title}</span>
                  <span class={["ab-tag", "ab-today__state", tag_class(item.state)]}>
                    {state_label(item.state)}
                  </span>
                  <span class="ab-meta ab-today__age">{ago(item.at, @now)}</span>
                  <span class="ab-today__action">{action_label(item.state)}</span>
                </button>
              </li>
            </ol>
          </section>

          <section id="today-running" class="ab-today__section" aria-labelledby="today-running-title">
            <div class="ab-sec__head">
              <h2 id="today-running-title">{gettext("Running now")}</h2>
              <span class="ab-sec__count">{length(@today.running)}</span>
            </div>

            <p :if={@today.running == []} class="ab-sec__empty">{gettext("Nothing running now.")}</p>

            <ol :if={@today.running != []} class="ab-today__list">
              <li :for={item <- @today.running}>
                <button
                  type="button"
                  class="ab-today__item"
                  phx-click="open_any"
                  phx-value-id={item.id}
                >
                  <span class="ab-today__repo">{item.repo}</span>
                  <span class="ab-today__num">#{item.number}</span>
                  <span class="ab-today__title">{item.title}</span>
                  <span class="ab-tag ab-tag--agent ab-today__state">
                    {item[:executor_name] || state_label(item.state)}
                  </span>
                  <span class="ab-meta ab-today__age">{elapsed(item[:started_at], @now)}</span>
                  <span class="ab-today__action">{gettext("Open")}</span>
                </button>
              </li>
            </ol>
          </section>
        </div>

        <section
          :if={@daily_summary}
          id="today-daily-report"
          class="ab-today__section"
          aria-label={gettext("Latest summary generated by the board")}
        >
          <.daily_summary entry={@daily_summary} tz_offset={@offset} />
        </section>
      </div>

      <div class="ab-today__insights">
        <section id="today-projects" class="ab-today__section" aria-labelledby="today-projects-title">
          <div class="ab-sec__head">
            <h2 id="today-projects-title">{gettext("By project")}</h2>
            <span class="ab-sec__count">{length(@projects)}</span>
          </div>
          <p :if={@projects == []} class="ab-sec__empty">{gettext("No tracked projects.")}</p>
          <div :if={@projects != []} class="ab-today__projects-wrap">
            <table class="ab-today__projects">
              <thead>
                <tr>
                  <th scope="col">{gettext("Project")}</th><th scope="col">{gettext("Needs you")}</th><th scope="col">
                    {gettext("Running")}
                  </th><th scope="col">{gettext("Queue")}</th><th scope="col">
                    {gettext("PRs today")}
                  </th><th scope="col">
                    {gettext("Reading")}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={project <- @projects}>
                  <th scope="row">
                    <button
                      type="button"
                      class="ab-today__project-link"
                      phx-click="select"
                      phx-value-repo={project.name}
                    >{project.name}</button>
                  </th>
                  <td data-label={gettext("Needs you")}>{project.needs}</td><td data-label={
                    gettext("Running")
                  }>
                    {project.running}
                  </td><td data-label={gettext("Queue")}>{project.queued}</td><td data-label={
                    gettext("PRs today")
                  }>
                    {project.merged}
                  </td>
                  <td
                    class={
                      if(project.unknown,
                        do: "ab-today__freshness ab-today__freshness--unknown",
                        else: "ab-today__freshness"
                      )
                    }
                    data-label={gettext("Reading")}
                  >
                    <span>{freshness_label(project)}</span>
                    <span :if={project.last_sync} class="ab-today__freshness-time">
                      {Time.since_label(project.last_sync.inserted_at, @offset, @now)}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section id="today-trend" class="ab-today__section" aria-labelledby="today-trend-title">
          <div class="ab-sec__head">
            <h2 id="today-trend-title">{gettext("Merged PRs · 7 days")}</h2>
            <span class="ab-sec__count">{gettext("%{count} in period", count: @trend_total)}</span>
          </div>
          <p class="ab-meta ab-today__note">
            {gettext("By merge date among PRs recorded by the board. Days follow your local time.")}
          </p>
          <ol class="ab-today__trend" aria-label={gettext("PRs merged in the last seven days")}>
            <li :for={bar <- @trend} aria-label={bar.description}>
              <span class="ab-today__bar-number">{bar.count}</span>
              <span class="ab-today__bar-track"><span
                class="ab-today__bar"
                style={"height: #{bar.height}%"}
              ></span></span>
              <span class="ab-today__bar-day">{bar.label}</span>
            </li>
          </ol>
        </section>
      </div>

      <section id="today-spend" class="ab-today__section" aria-label={gettext("Daily spend")}>
        <div class="ab-sec__head">
          <h2>{gettext("Usage today")}</h2>
        </div>
        <div class="ab-today__spend">
          <span :for={row <- @spend_rows} class="ab-today__money" title={row.title}>
            {row.label} <b>{row.value}</b>
          </span>
        </div>
      </section>
    </section>
    """
  end

  defp freshness_label(%{last_sync: nil}), do: gettext("not read")
  defp freshness_label(%{unknown: true, last_sync: %{kind: "sync_error"}}), do: gettext("failed")
  defp freshness_label(%{unknown: true}), do: gettext("stale")
  defp freshness_label(_project), do: gettext("current")

  defp trend_bars([]), do: []

  defp trend_bars(trend) do
    top = trend |> Enum.map(& &1.count) |> Enum.max() |> max(1)
    today = List.last(trend).date

    Enum.map(trend, fn point ->
      %{
        count: point.count,
        label: Time.short_day_label(point.date, today),
        description:
          gettext("%{day}: %{count} PRs merged",
            day: Time.day_label(point.date, today),
            count: point.count
          ),
        height: round(point.count / top * 100)
      }
    end)
  end

  defp spend_rows(nil) do
    for source <- @sources,
        do: %{
          label: Map.fetch!(@labels, source),
          value: gettext("unknown"),
          title: gettext("No usage ledger reading for today")
        }
  end

  defp spend_rows(spend) do
    Enum.map(@sources, fn source ->
      %{
        label: Map.fetch!(@labels, source),
        value: value(source, spend),
        title: title(source, spend)
      }
    end)
  end

  defp value("codex", spend) do
    case spend.quota do
      %{used_percent: percent} ->
        gettext("%{percent}% of weekly quota", percent: percent(percent))

      nil ->
        gettext("unknown")
    end
  end

  defp value(source, spend) do
    case Map.get(spend.by_source, source) do
      nil ->
        gettext("did not run")

      %{status: :none} ->
        gettext("did not run")

      %{status: :unknown} ->
        gettext("unknown")

      %{cost: nil} ->
        gettext("unknown")

      %{cost: %{micros: micros, complete?: true}} ->
        "≈ #{money(micros)}"

      %{cost: %{micros: micros}} ->
        "≥ #{money(micros)}"
    end
  end

  defp title("codex", spend) do
    case spend.quota do
      %{used_percent: percent, resets_at: at} when is_binary(at) ->
        gettext("ChatGPT plan weekly quota: %{percent}% used; resets at %{time}.",
          percent: percent(percent),
          time: at
        )

      %{used_percent: percent} ->
        gettext("ChatGPT plan weekly quota: %{percent}% used.", percent: percent(percent))

      nil ->
        gettext("No Codex weekly quota reading")
    end
  end

  defp title("claude_code", _spend),
    do: gettext("Estimated at the Claude Max list price; it is a reference, not the bill.")

  defp title("dsh", _spend), do: gettext("Estimated in USD from the board's pricing table.")

  defp date_label(now, offset) do
    at = DateTime.add(now, -offset * 60, :second)

    if Gettext.get_locale(AgentBoardWeb.Gettext) == "pt_BR" do
      weekdays =
        ~w(segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado domingo)

      months =
        ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)

      "#{Enum.at(weekdays, Date.day_of_week(DateTime.to_date(at)) - 1)} #{at.day} de #{Enum.at(months, at.month - 1)}"
    else
      gettext("%{day}, %{date} %{month}",
        day: Time.weekday(DateTime.to_date(at)),
        date: at.day,
        month: Time.month(DateTime.to_date(at))
      )
    end
  end

  defp state_label("blocked"), do: gettext("blocked")
  defp state_label("question"), do: gettext("question")
  defp state_label("ready"), do: gettext("ready for review")
  defp state_label("running"), do: gettext("running")
  defp state_label(state), do: state

  defp action_label("question"), do: gettext("Respond")
  defp action_label("ready"), do: gettext("Review")
  defp action_label(_state), do: gettext("Open")

  defp elapsed(nil, _now), do: gettext("now")

  defp elapsed(%DateTime{} = at, now),
    do: AgentBoardWeb.Time.duration(AgentBoardWeb.Time.age_seconds(at, now))

  defp tag_class("blocked"), do: "ab-tag--halt"
  defp tag_class("question"), do: "ab-tag--you"
  defp tag_class("ready"), do: "ab-tag--you"
  defp tag_class(_state), do: "ab-tag--agent"

  defp ago(nil, _now), do: gettext("now")
  defp ago(at, now), do: Time.ago(Time.age_seconds(at, now))

  defp percent(value) when is_float(value),
    do: value |> :erlang.float_to_binary(decimals: 0) |> String.replace(".", ",")

  defp percent(value), do: Integer.to_string(value)

  defp money(micros), do: AgentBoardWeb.Numbers.usd(micros)
end
