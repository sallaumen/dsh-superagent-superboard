defmodule AgentBoardWeb.BoardComponents.Card do
  @moduledoc "The board's card region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation

  alias AgentBoardWeb.BoardComponents.DataAge

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
          "unknown"}</a>
        <span :if={is_nil(@item.url)}>{@item.title || "unknown"}</span>
      </div>
      <div :if={review_badge(@item) || checks_badge(@item)} class="item-signals">
        <span :if={review_badge(@item)} class={review_badge_class(@item)}>{review_badge(@item)}</span>
        <span :if={checks_badge(@item)} class={checks_badge_class(@item)}>{checks_badge(@item)}</span>
      </div>
      <DataAge.stamp
        id={"#{@id}-age"}
        at={if @state == :merged, do: @item.merged_at, else: @item.updated_at}
        label={if @state == :merged, do: "Merged", else: "Record updated"}
      />
      <div :if={@state in [:running, :ready, :blocked, :queued]} class="task-actions">
        <button
          phx-click="open"
          id={"open-task-#{@item.id}"}
          data-panel-trigger
          aria-haspopup="dialog"
          phx-value-id={@item.id}
          aria-label={"Open task: " <> (@item.title || "unknown")}
        >Open</button>
        <button
          phx-click="act"
          phx-value-id={@item.id}
          phx-value-action="stop"
          phx-disable-with="Stopping…"
          title="Closes the GitHub issue and stops this task"
          aria-label={"Stop task: " <> (@item.title || "unknown")}
        >Stop</button>
        <button
          phx-click="act"
          phx-value-id={@item.id}
          phx-value-action="archive"
          phx-disable-with="Archiving…"
          title="Hides this task from the board; keeps its history"
          aria-label={"Archive task: " <> (@item.title || "unknown")}
        >Archive</button>
      </div>
    </article>
    """
  end
end
