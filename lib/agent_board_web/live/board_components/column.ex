defmodule AgentBoardWeb.BoardComponents.Column do
  @moduledoc "The board's column region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id={@id}
      aria-label={@title <> " tasks"}
      tabindex="0"
      class="board-column min-w-0 overflow-y-auto bg-base-100 p-4 lg:max-h-[55vh]"
    >
      <h2 class="sticky top-0 z-10 mb-3 flex items-baseline justify-between bg-base-100 py-1 gap-2 text-[11px] uppercase tracking-[0.16em] text-base-content/75">
        <span>{@title}</span>
        <span class="rounded-full bg-base-200 px-2 py-0.5 text-[10px] tabular-nums">
          {if @state == :merged, do: "latest "}{length(@items)}
        </span>
      </h2>

      <.live_component
        :for={item <- @items}
        module={AgentBoardWeb.BoardComponents.Card}
        id={"#{if @state == :merged, do: "pull", else: "task"}-#{item.id}"}
        item={item}
        state={@state}
      />

      <p :if={@items == []} class="text-xs text-base-content/75">
        {empty_copy(@state)}
      </p>
    </section>
    """
  end
end
