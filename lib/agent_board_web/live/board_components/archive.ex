defmodule AgentBoardWeb.BoardComponents.Archive do
  @moduledoc "Scrollable merged pull request history using only loaded records."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation, only: [empty_copy: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} aria-label={gettext("Merged PR History")} tabindex="-1" class="board-archive">
      <header class="archive-heading">
        <div class="archive-title">
          <h2>{gettext("Merged PRs")}</h2>
          <span
            class="archive-count"
            aria-label={gettext("%{count} pull requests loaded", count: length(@items))}
          >
            {gettext("%{count} loaded", count: length(@items))}
          </span>
        </div>
        <span class="archive-scope">{gettext("Newest first")}</span>
      </header>
      <.live_component
        :if={@items != []}
        module={AgentBoardWeb.BoardComponents.MergeTrend}
        id="merge-trend"
        items={@items}
        has_more={@has_more}
      />
      <div
        id="merged-list"
        class="archive-list"
        role="region"
        tabindex="0"
        aria-label={gettext("Merged PR List")}
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
          {gettext("Scroll to older PRs")}
        </p>
        <p :if={@items != [] && !@has_more} class="archive-tail">{gettext("End of saved history")}</p>
      </div>
    </section>
    """
  end
end
