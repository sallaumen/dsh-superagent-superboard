defmodule AgentBoardWeb.BoardComponents.Archive do
  @moduledoc "Compact merged pull request history using only the loaded board records."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation, only: [empty_copy: 1]

  @preview_count 5

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :remaining, Enum.drop(assigns.items, @preview_count))

    ~H"""
    <section id={@id} aria-label="Merged tasks" class="board-archive">
      <div class="archive-heading">
        <h2>Merged <span class="archive-count">{length(@items)}</span></h2>
        <span class="board-eyebrow">Recent history · latest {length(@items)} loaded</span>
      </div>
      <div id="merged-preview">
        <.live_component
          :for={item <- Enum.take(@items, 5)}
          module={AgentBoardWeb.BoardComponents.Card}
          id={"pull-#{item.id}"}
          item={item}
          state={:merged}
        />
      </div>
      <p :if={@items == []} class="lane-empty">{empty_copy(:merged)}</p>
      <details :if={@remaining != []} id="merged-history" class="archive-history">
        <summary>Show {length(@remaining)} more merged pull requests</summary>
        <div
          class="archive-history-list"
          role="region"
          tabindex="0"
          aria-label="More merged pull requests"
        >
          <.live_component
            :for={item <- @remaining}
            module={AgentBoardWeb.BoardComponents.Card}
            id={"pull-#{item.id}"}
            item={item}
            state={:merged}
          />
        </div>
      </details>
    </section>
    """
  end
end
