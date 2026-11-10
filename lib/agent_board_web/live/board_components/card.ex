defmodule AgentBoardWeb.BoardComponents.Card do
  @moduledoc "The board's card region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation

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
      <span class="item-number">{if @item.number, do: "##{@item.number}", else: "unknown"}</span>
      <div class="item-title">
        <a :if={@item.url} href={@item.url} target="_blank" rel="noopener noreferrer">{@item.title ||
          "unknown"}<span class="sr-only">{gettext("(opens GitHub in a new tab)")}</span></a>
        <span :if={is_nil(@item.url)}>{@item.title || "unknown"}</span>
        <MergeLog.task_door
          :if={@state == :merged and Map.get(@item, :closes_issues, []) != []}
          pull={@item.number}
          issue={hd(@item.closes_issues)}
        />
      </div>
      <div class="item-signals">
        <span :if={review_badge(@item)} class={review_badge_class(@item)}>{review_badge(@item)}</span>
        <span class={ci_class(@ci)} title={elem(@ci, 2)}>{elem(@ci, 1)}</span>
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
end
