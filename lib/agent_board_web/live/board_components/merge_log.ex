defmodule AgentBoardWeb.BoardComponents.MergeLog do
  @moduledoc "Merged: seven days side by side, newest first, each with its record."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.StatusMark, only: [glyph: 1]
  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1]

  alias AgentBoardWeb.BoardComponents.Concluded
  alias AgentBoardWeb.Time

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
          <span class="ab-meta"><.week log={@log} frozen={@frozen} /></span>
        </summary>
        <div class="ab-fold__body">
          <div class="ab-sec__head">
            <h2 id="sec-log-title">{gettext("Merged")}</h2>
            <span class="ab-sec__count"><.week log={@log} frozen={@frozen} /></span>
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
                <span class="ab-day__count"><.day_count day={day} /></span>
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
                phx-value-list="prs"
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
                phx-value-list="prs"
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

  # A PR that closes an issue opens its task on the board, where the whole
  # conversation is; GitHub stays one small link away. One that closes
  # nothing has no task, so the row is GitHub.
  defp pr_row(%{pr: %{closes: [issue | _]}} = assigns) do
    assigns = assign(assigns, :issue, issue)

    ~H"""
    <button
      type="button"
      class="ab-pr"
      phx-click="open_pr_task"
      phx-value-number={@pr.number}
      aria-label={
        gettext("PR #%{number}: %{title}. Open task #%{issue} on the board",
          number: @pr.number,
          title: @pr.title,
          issue: @issue
        )
      }
    >
      <.pr_body pr={@pr} />
    </button>
    <.github_link :if={@pr.url} number={@pr.number} url={@pr.url} />
    """
  end

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
      <.pr_body pr={@pr} />
    </a>
    """
  end

  attr :pr, :map, required: true

  defp pr_body(assigns) do
    ~H"""
    <.glyph kind={:done} />
    <span class="ab-pr__title">
      <span class="ab-need__id">#{@pr.number}</span> {@pr.title}
    </span>
    <span class="ab-pr__meta">
      <span
        class={[
          "ab-tag",
          @pr.ci == "fail" && "ab-tag--halt",
          @pr.ci == "pass" && @pr.ciLocal && "ab-tag--agent"
        ]}
        title={@pr.ciTitle}
      >
        <.glyph :if={@pr.ci == "fail"} kind={:cifail} />
        {@pr.ciNote}
      </span>
      <span class="ab-meta">{@pr.review}</span>
      <span class="ab-data-sm ab-faint">{@pr.at}</span>
      <.task_cost entries={@pr.cost} />
    </span>
    """
  end

  @doc """
  What the PR's task cost, in each executor's unit. Nothing at all when no
  cost is attributed: absent, never a zero.
  """
  attr :entries, :list, default: nil

  def task_cost(assigns) do
    ~H"""
    <span
      :if={@entries}
      class="ab-pr__cost ab-data-sm"
      title={
        gettext(
          "What the executor spent on this PR's task in the last 90 days. A task delivered by several PRs shows its whole cost on each."
        )
      }
    >
      {Concluded.cost_text(@entries)}
    </span>
    """
  end

  @doc "The PR on GitHub, beside a row that opens its task on the board."
  attr :number, :integer, required: true
  attr :url, :string, required: true

  def github_link(assigns) do
    ~H"""
    <a
      class="ab-more ab-pr__task"
      href={@url}
      target="_blank"
      rel="noopener noreferrer"
      aria-label={gettext("PR #%{number} on GitHub (opens in a new tab)", number: @number)}
    >
      GitHub <.ico name="ext" />
    </a>
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

  # The day says what it delivered first; "and N more" below says what is hidden.
  attr :day, :map, required: true

  defp day_count(%{day: %{n: 0}} = assigns), do: ~H"0"

  defp day_count(assigns) do
    ~H"""
    <b class="ab-delivered">{delivered(@day.issues, @day.issues)}</b>
    <span class="ab-day__prs">· {ngettext("%{amount} PR", "%{amount} PRs", @day.n, amount: @day.n)}</span>
    """
  end

  # Issues lead: an issue is a delivery; a PR is how it got there.
  attr :log, :map, required: true
  attr :frozen, :boolean, required: true

  defp week(assigns) do
    ~H"""
    <b class="ab-delivered">{delivered(@log.issues, Time.frozen_count(@log.issues, @frozen))}</b>
    · {gettext("%{prs} in 7 days",
      prs:
        ngettext("%{amount} PR", "%{amount} PRs", @log.total,
          amount: Time.frozen_count(@log.total, @frozen)
        )
    )}
    """
  end

  @doc "How many issues were delivered, as Merged and the daily summary say it."
  def delivered(0, _shown), do: gettext("no issues delivered")

  def delivered(n, shown),
    do: ngettext("%{amount} issue delivered", "%{amount} issues delivered", n, amount: shown)
end
