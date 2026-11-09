defmodule AgentBoardWeb.BoardComponents.MergeLog do
  @moduledoc "Mesclados: seven days in dots, then the record by day."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]
  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1]

  attr :log, :map, required: true
  attr :frozen, :boolean, default: false
  attr :has_history, :boolean, default: false
  attr :idle, :boolean, default: false

  def merge_log(assigns) do
    groups = assigns.log.groups
    hidden = max(length(groups) - 3, 0)

    assigns =
      assigns
      |> assign(:groups, groups)
      |> assign(:hidden_groups, hidden)

    ~H"""
    <section id="sec-log" aria-labelledby="sec-log-title">
      <div class="ab-sec__head">
        <h2 id="sec-log-title">{gettext("Merged")}</h2>
        <span class="ab-sec__count">{count(@log.total, @frozen)} em 7 dias</span>
        <span class="ab-top__spacer"></span>
        <button
          :if={@has_history}
          type="button"
          class="ab-btn ab-btn--quiet ab-btn--sm"
          phx-click="show_panel"
          phx-value-panel="history"
          data-panel-trigger
        >
          {gettext("History")} <.ico name="ext" />
        </button>
      </div>

      <div class="ab-week" aria-label={gettext("Merges per day, last 7 days")}>
        <div
          :for={day <- @log.days}
          class={["ab-day", day.today && "is-today"]}
          title={
            "#{day.n} merges" <>
              if(day.fail > 0, do: ", #{day.fail} com CI local falhando", else: "") <>
              if(day.ok > 0, do: ", #{day.ok} com CI local ok", else: "")
          }
        >
          <div class="ab-day__dots">
            <span :if={day.n == 0} class="ab-day__zero" aria-hidden="true"></span>
            <%= if day.n > 0 do %>
              <i
                :for={index <- 1..min(day.n, 8)}
                class={index <= day.fail && "is-fail"}
                aria-hidden="true"
              ></i>
            <% end %>
            <em :if={day.n > 0}>{day.n}</em>
          </div>
          <span class="ab-day__label">{day.label}</span>
        </div>
      </div>

      <div :if={@log.total == 0} class="ab-sec__empty">{gettext("No PRs merged this week.")}</div>

      <div :if={@log.total > 0} class="ab-log">
        <h3 class="ab-log__title">{gettext("7-day history")}</h3>
        <div :for={group <- @groups} class="ab-log__group">
          <div class="ab-log__day">
            <span class="ab-label">{group.label}</span>
            <span class="ab-data-sm ab-faint">
              {length(group.items)}{if group.more > 0, do: " de #{group.n}", else: ""}
            </span>
          </div>

          <a
            :for={pr <- group.items}
            class="ab-pr"
            href={pr.url}
            target="_blank"
            rel="noopener noreferrer"
            aria-label={"PR ##{pr.number}: #{pr.title} (abre o GitHub em nova aba)"}
          >
            <.glyph kind={:done} />
            <span class="ab-pr__title">
              <span class="ab-need__id">#{pr.number}</span> {pr.title}
            </span>
            <span class="ab-pr__meta">
              <span
                class={[
                  "ab-tag",
                  pr.ci == "fail" && "ab-tag--halt",
                  pr.ci == "pass" && pr.ciNote == "CI local ok" && "ab-tag--agent"
                ]}
                title={pr.ciTitle}
              >
                <.glyph :if={pr.ci == "fail"} kind={:cifail} />
                {pr.ciNote}
              </span>
              <span class="ab-meta">{pr.review}</span>
              <span class="ab-data-sm ab-faint">{pr.at}</span>
            </span>
          </a>
        </div>
        <button
          :if={@hidden_groups > 0}
          type="button"
          class="ab-more"
          phx-click="show_panel"
          phx-value-panel="history"
          data-panel-trigger
        >
          {ngettext("%{count} more day in history", "%{count} more days in history", @hidden_groups)}
        </button>
      </div>
    </section>
    """
  end

  defp count(0, _frozen), do: "0"
  defp count(n, true), do: "≥#{n}"
  defp count(n, false), do: "#{n}"
end
