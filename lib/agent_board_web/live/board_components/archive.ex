defmodule AgentBoardWeb.BoardComponents.Archive do
  @moduledoc "Scrollable merged pull request history using only loaded records."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation, only: [empty_copy: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} aria-label="Histórico de PRs mesclados" tabindex="-1" class="board-archive">
      <header class="archive-heading">
        <div class="archive-title">
          <h2>PRs mesclados</h2>
          <span class="archive-count" aria-label={"#{length(@items)} pull requests loaded"}>
            {length(@items)} carregados
          </span>
        </div>
        <span class="archive-scope">Mais novos primeiro</span>
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
        aria-label="Lista de PRs mesclados"
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
          Role para PRs mais antigos
        </p>
        <p :if={@items != [] && !@has_more} class="archive-tail">Fim do histórico salvo</p>
      </div>
    </section>
    """
  end
end
