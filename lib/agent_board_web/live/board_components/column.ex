defmodule AgentBoardWeb.BoardComponents.Column do
  @moduledoc "The board's column region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id={@id}
      aria-label={"#{@title} tasks, #{@total} total"}
      tabindex="0"
      data-state={@state}
      data-attention={to_string(@state == :blocked and @total > 0)}
      class={["board-column bg-base-100", @items == [] && "is-empty"]}
    >
      <h2 class="lane-heading">
        <span>{@title}</span>
        <span class="lane-count">
          {@total}
        </span>
      </h2>

      <div
        :if={@items != []}
        id={"#{@id}-list"}
        class="lane-items"
        role="region"
        tabindex="0"
        aria-label={@title <> " task list"}
        phx-viewport-bottom={if @has_more, do: "load_more_tasks"}
      >
        <.live_component
          :for={item <- @items}
          module={AgentBoardWeb.BoardComponents.Card}
          id={"task-#{item.id}"}
          item={item}
          state={@state}
        />
        <p
          :if={@has_more}
          id={"task-tail-#{@state}-#{List.last(@items).id}"}
          class="lane-tail"
        >
          Scroll for more {@title} tasks · {length(@items)} of {@total} loaded
        </p>
      </div>

      <p :if={@items == []} class="lane-empty">
        {empty_copy(@state)}
      </p>
    </section>
    """
  end
end
