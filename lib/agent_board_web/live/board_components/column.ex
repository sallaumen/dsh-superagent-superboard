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
      data-state={@state}
      class={["board-column bg-base-100", @items == [] && "is-empty"]}
    >
      <h2 class="lane-heading">
        <span>{@title}</span>
        <span class="lane-count">
          {length(@items)}
        </span>
      </h2>

      <div
        :if={@items != []}
        class="lane-items"
        role="region"
        tabindex="0"
        aria-label={@title <> " task list"}
      >
        <.live_component
          :for={item <- @items}
          module={AgentBoardWeb.BoardComponents.Card}
          id={"task-#{item.id}"}
          item={item}
          state={@state}
        />
      </div>

      <p :if={@items == []} class="lane-empty">
        {empty_copy(@state)}
      </p>
    </section>
    """
  end
end
