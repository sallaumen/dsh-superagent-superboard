defmodule AgentBoardWeb.BoardComponents.HeaderActions do
  @moduledoc "Work and inspection panels available from the board header."
  use AgentBoardWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <nav id="board-tools" aria-label="Board tools" class="board-tools">
      <button
        :if={@repo}
        id="open-intake"
        type="button"
        phx-click="show_panel"
        phx-value-panel="intake"
        data-panel-trigger
        aria-haspopup="dialog"
        aria-controls="panel-intake"
        class="board-primary-action"
      ><.icon name="hero-scissors" class="size-4 shrink-0" />Split a request</button>

      <details id="board-actions" phx-hook="BoardMenu" data-board-menu class="board-actions">
        <summary>
          <.icon name="hero-rectangle-stack" class="size-4 shrink-0" /> Panels
          <.icon name="hero-chevron-down" class="board-menu-chevron size-3 shrink-0" />
        </summary>
        <div class="board-actions-menu">
          <h2>Board panels</h2>
          <%= if @repo do %>
            <p class="board-actions-label">Work</p>
            <button
              id="open-create"
              type="button"
              phx-click="show_panel"
              phx-value-panel="create"
              data-panel-trigger
              aria-haspopup="dialog"
              aria-controls="panel-create"
            >
              <.icon name="hero-plus" class="size-4 shrink-0" />
              <span><strong>New task</strong><small>Start from a title and description</small></span>
            </button>
            <p class="board-actions-label">Inspect</p>
            <button
              id="open-activity"
              type="button"
              phx-click="show_panel"
              phx-value-panel="activity"
              data-panel-trigger
              aria-haspopup="dialog"
              aria-controls="panel-activity"
            >
              <.icon name="hero-clock" class="size-4 shrink-0" />
              <span><strong>Activity</strong><small>Syncs and recent events</small></span>
            </button>
            <button
              id="open-ai"
              type="button"
              phx-click="show_panel"
              phx-value-panel="ai"
              data-panel-trigger
              aria-haspopup="dialog"
              aria-controls="panel-ai"
            >
              <.icon name="hero-cpu-chip" class="size-4 shrink-0" />
              <span><strong>AI calls</strong><small>Models, tokens and cost</small></span>
            </button>
          <% else %>
            <p class="board-actions-empty">Select a repository to open its work panels.</p>
          <% end %>
        </div>
      </details>
    </nav>
    """
  end
end
