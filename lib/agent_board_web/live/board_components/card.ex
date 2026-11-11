defmodule AgentBoardWeb.BoardComponents.Card do
  @moduledoc "The board's card region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  alias AgentBoardWeb.BoardComponents.DataAge
  alias AgentBoardWeb.BoardComponents.MergeLog

  @impl true
  def render(assigns) do
    ~H"""
    <article
      id={@id}
      data-state={@state}
      class={["board-card", if(@state == :merged, do: "archive-row", else: "task-card")]}
    >
      <span class="item-number">{if @item.number, do: "##{@item.number}", else: gettext("unknown")}</span>
      <div class="item-title">
        <%= if task_door?(@state, @item) do %>
          <%!-- A merged PR that closes an issue opens its task on the board. --%>
          <button
            type="button"
            class="item-title__open"
            phx-click="open_pr_task"
            phx-value-number={@item.number}
            aria-label={
              gettext("PR #%{number}: %{title}. Open task #%{issue} on the board",
                number: @item.number,
                title: @item.title || gettext("unknown"),
                issue: hd(@item.closes_issues)
              )
            }
          >{@item.title || gettext("unknown")}</button>
          <MergeLog.github_link :if={@item.url} number={@item.number} url={@item.url} />
        <% else %>
          <a :if={@item.url} href={@item.url} target="_blank" rel="noopener noreferrer">{@item.title ||
            gettext("unknown")}<span class="sr-only">{gettext("(opens GitHub in a new tab)")}</span></a>
          <span :if={is_nil(@item.url)}>{@item.title || gettext("unknown")}</span>
        <% end %>
      </div>
      <div class="item-signals">
        <span :if={review_badge(@item)} class={review_badge_class(@item)}>{review_badge(@item)}</span>
        <span class={ci_class(@ci)} title={elem(@ci, 2)}>{elem(@ci, 1)}</span>
        <MergeLog.task_cost :if={@state == :merged} entries={assigns[:cost]} />
      </div>
      <DataAge.stamp
        id={"#{@id}-age"}
        at={if @state == :merged, do: @item.merged_at, else: @item.updated_at}
        label={
          if @state == :merged, do: pgettext("stamp", "Merged"), else: pgettext("stamp", "Updated")
        }
      />
    </article>
    """
  end

  # The same answer the merge log gives (`AgentBoard.Lanes.ci/2`): the local
  # gate first, and a red remote check alone is unknown, not a failure.
  defp ci_class({"pass", _note, _title}), do: "text-success"
  defp ci_class({"fail", _note, _title}), do: "text-error"
  defp ci_class(_ci), do: "text-base-content/75"

  defp review_badge(%{review_state: "approved"}), do: gettext("approved")
  defp review_badge(%{review_state: "changes_requested"}), do: gettext("changes requested")
  defp review_badge(%{review_state: "pending"}), do: gettext("review pending")
  # "none" is a real answer: the pull has no reviews. Saying it is more honest
  # than hiding the badge and letting the reader guess.
  defp review_badge(%{review_state: "none"}), do: gettext("no review")
  defp review_badge(_item), do: nil

  defp review_badge_class(%{review_state: "approved"}), do: "text-success"
  defp review_badge_class(%{review_state: "changes_requested"}), do: "text-error"
  defp review_badge_class(_item), do: "text-base-content/75"

  defp task_door?(:merged, item), do: Map.get(item, :closes_issues, []) not in [nil, []]
  defp task_door?(_state, _item), do: false
end
