defmodule AgentBoardWeb.BoardComponents.Archive do
  @moduledoc "Scrollable merged pull request history using only loaded records."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation, only: [empty_copy: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} aria-label="Merged tasks" class="board-archive">
      <div class="archive-heading">
        <h2>Merged <span class="archive-count">{length(@items)}</span></h2>
        <span class="board-eyebrow">Recent history · latest {length(@items)} loaded</span>
      </div>
      <.live_component
        :if={@items != []}
        module={AgentBoardWeb.BoardComponents.MergeTrend}
        id="merge-trend"
        items={@items}
      />
      <div
        id="merged-list"
        class="archive-list"
        role="region"
        tabindex="0"
        aria-label="Merged pull request list"
      >
        <.live_component
          :for={item <- @items}
          module={AgentBoardWeb.BoardComponents.Card}
          id={"pull-#{item.id}"}
          item={item}
          state={:merged}
        />
        <p :if={@items == []} class="lane-empty">{empty_copy(:merged)}</p>
      </div>
    </section>
    """
  end
end
