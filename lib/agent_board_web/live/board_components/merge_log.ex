defmodule AgentBoardWeb.BoardComponents.MergeLog do
  @moduledoc "Merged: seven days side by side, newest first, each with its record."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]
  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1]

  attr :log, :map, required: true
  attr :frozen, :boolean, default: false
  attr :has_history, :boolean, default: false

  def merge_log(assigns) do
    days =
      assigns.log.days
      |> Enum.reverse()
      |> Enum.map(fn day ->
        Map.put(day, :group, Enum.find(assigns.log.groups, &(&1.date == day.date)))
      end)

    assigns = assign(assigns, :days, days)

    ~H"""
    <section id="sec-log" aria-labelledby="sec-log-title">
      <%!-- On a phone the lane is one line until it is opened (BoardFold). --%>
      <details id="fold-log" class="ab-fold ab-fold--log" data-mobile-fold open phx-hook="BoardFold">
        <summary class="ab-fold__summary">
          <span>{gettext("Merged")}</span>
          <span class="ab-meta">{count(@log.total, @frozen)} {gettext("in 7 days")}</span>
        </summary>
        <div class="ab-fold__body">
          <div class="ab-sec__head">
            <h2 id="sec-log-title">{gettext("Merged")}</h2>
            <span class="ab-sec__count">
              {count(@log.total, @frozen)} {gettext("in 7 days")}
            </span>
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

          <div class="ab-days" role="list" aria-label={gettext("Merges per day, last 7 days")}>
            <div
              :for={day <- @days}
              id={"log-day-#{day.date}"}
              class={["ab-day", day.today && "is-today", day.n == 0 && "is-empty"]}
              role="listitem"
            >
              <div class="ab-day__head">
                <b class="ab-day__label">{day.label}</b>
                <span class={["ab-day__count", group_extra(day.group) != [] && "ab-day__count--short"]}>
                  {day_count(day)}
                </span>
                <span :if={group_extra(day.group) != []} class="ab-day__count ab-day__count--wide">
                  {day_count_wide(day)}
                </span>
              </div>

              <div class="ab-day__dots" aria-hidden="true">
                <%= if day.n > 0 do %>
                  <i
                    :for={index <- 1..min(day.n, 12)}
                    class={index <= day.fail && "is-fail"}
                  ></i>
                  <em :if={day.n > 12}>+{day.n - 12}</em>
                <% end %>
              </div>

              <.pr_row :for={pr <- group_items(day.group)} pr={pr} />
              <div :if={group_extra(day.group) != []} class="ab-day__extra">
                <.pr_row :for={pr <- group_extra(day.group)} pr={pr} />
              </div>

              <button
                :if={group_more(day.group) > 0}
                type="button"
                class={["ab-more ab-day__more", group_extra(day.group) != [] && "ab-day__more--short"]}
                phx-click="show_panel"
                phx-value-panel="history"
                data-panel-trigger
              >
                {gettext("and %{count} more", count: group_more(day.group))}
              </button>
              <button
                :if={group_more_wide(day.group) > 0}
                type="button"
                class="ab-more ab-day__more ab-day__more--wide"
                phx-click="show_panel"
                phx-value-panel="history"
                data-panel-trigger
              >
                {gettext("and %{count} more", count: group_more_wide(day.group))}
              </button>

              <span :if={day.n == 0} class="ab-day__none">{gettext("No merges.")}</span>
            </div>
          </div>
        </div>
      </details>
    </section>
    """
  end

  attr :pr, :map, required: true

  defp pr_row(assigns) do
    ~H"""
    <a
      class="ab-pr"
      href={@pr.url}
      target="_blank"
      rel="noopener noreferrer"
      aria-label={
        "PR ##{@pr.number}: #{@pr.title} " <>
          gettext("(opens GitHub in a new tab)")
      }
    >
      <.glyph kind={:done} />
      <span class="ab-pr__title">
        <span class="ab-need__id">#{@pr.number}</span> {@pr.title}
      </span>
      <span class="ab-pr__meta">
        <span
          class={[
            "ab-tag",
            @pr.ci == "fail" && "ab-tag--halt",
            @pr.ci == "pass" && @pr.ciNote == gettext("Local CI passed") && "ab-tag--agent"
          ]}
          title={@pr.ciTitle}
        >
          <.glyph :if={@pr.ci == "fail"} kind={:cifail} />
          {@pr.ciNote}
        </span>
        <span class="ab-meta">{@pr.review}</span>
        <span class="ab-data-sm ab-faint">{@pr.at}</span>
      </span>
    </a>
    <.task_door :if={@pr.closes != []} pull={@pr.number} issue={hd(@pr.closes)} />
    """
  end

  @doc "The way from a merged PR into the task it closes; the row itself opens GitHub."
  attr :pull, :integer, required: true
  attr :issue, :integer, required: true

  def task_door(assigns) do
    ~H"""
    <button
      type="button"
      class="ab-more ab-pr__task"
      phx-click="open_pr_task"
      phx-value-number={@pull}
      aria-label={gettext("Open task #%{number} on the board", number: @issue)}
    >
      {gettext("task #%{number}", number: @issue)}
    </button>
    """
  end

  defp group_items(nil), do: []
  defp group_items(group), do: group.items

  defp group_more(nil), do: 0
  defp group_more(group), do: group.more

  # What a wide window adds to the day: the rows past the first three, and
  # what is still left for the history after them.
  defp group_extra(nil), do: []
  defp group_extra(group), do: group.extra

  defp group_more_wide(nil), do: 0
  defp group_more_wide(group), do: group.more_wide

  defp day_count_wide(%{n: n, group: %{items: items, extra: extra, more_wide: more}})
       when more > 0,
       do: gettext("%{shown} of %{total}", shown: length(items) + length(extra), total: n)

  defp day_count_wide(%{n: n}), do: "#{n}"

  defp day_count(%{n: 0}), do: "0"

  defp day_count(%{n: n, group: %{items: items, more: more}}) when more > 0,
    do:
      gettext("%{shown} of %{total}",
        shown: length(items),
        total: n
      )

  defp day_count(%{n: n}), do: "#{n}"

  defp count(0, _frozen), do: "0"
  defp count(n, true), do: "≥#{n}"
  defp count(n, false), do: "#{n}"
end
