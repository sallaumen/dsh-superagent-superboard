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
          "unknown"}<span class="sr-only">{gettext("(opens GitHub in a new tab)")}</span></a>
        <span :if={is_nil(@item.url)}>{@item.title || "unknown"}</span>
      </div>
      <div :if={review_badge(@item) || checks_badge(@item)} class="item-signals">
        <span :if={review_badge(@item)} class={review_badge_class(@item)}>{review_badge(@item)}</span>
        <span :if={checks_badge(@item)} class={checks_badge_class(@item)}>{checks_badge(@item)}</span>
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
end
