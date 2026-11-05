defmodule AgentBoardWeb.BoardComponents.Archive do
  @moduledoc "Scrollable merged pull request history using only loaded records."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation, only: [empty_copy: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} aria-label="Merged pull request history" tabindex="-1" class="board-archive">
      <header class="archive-heading">
        <div class="archive-title">
          <h2>Merged PRs</h2>
          <span class="archive-count" aria-label={"#{length(@items)} pull requests loaded"}>
            {length(@items)} loaded
          </span>
        </div>
        <span class="archive-scope">Newest first</span>
      </header>
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
        phx-viewport-bottom={if @has_more, do: "load_more_merged"}
      >
        <.live_component
          :for={item <- @items}
          module={AgentBoardWeb.BoardComponents.Card}
          id={"pull-#{item.id}"}
          item={item}
          state={:merged}
        />
        <p :if={@items == []} class="lane-empty">{empty_copy(:merged)}</p>
        <p
          :if={@has_more && @items != []}
          id={"merged-tail-#{List.last(@items).id}"}
          class="archive-tail"
        >
          Scroll for older pull requests
        </p>
        <p :if={@items != [] && !@has_more} class="archive-tail">End of saved history</p>
      </div>
    </section>
    """
  end
end
