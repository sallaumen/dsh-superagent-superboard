defmodule AgentBoardWeb.BoardComponents.Header do
  @moduledoc "The board's header region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation

  alias AgentBoardWeb.BoardComponents.DataAge

  @impl true
  def render(assigns) do
    ~H"""
    <header id={@id} class="board-header">
      <div class="board-topbar">
        <div class="board-identity">
          <div class="flex flex-wrap items-baseline gap-2">
            <h1 class="text-lg tracking-[0.16em] uppercase">Agent board</h1>
            <span class="text-[10px] text-base-content/75">the agent's work, live</span>
          </div>
        </div>
        <div class="board-repository">
          <span class="board-eyebrow">Repository</span>
          <form id="repo-select" phx-change="select" class="repository-select">
            <select
              name="repo"
              aria-label="Repository"
              class="border border-base-content/10 bg-base-200 px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary"
            >
              <option :if={@repo == nil} value="">select a repository</option>
              <option
                :for={r <- @repos}
                value={"#{r.owner}/#{r.name}"}
                selected={@repo && @repo.id == r.id}
              >
                {r.owner}/{r.name}
              </option>
            </select>
          </form>
        </div>
        <details id="repository-settings" class="repository-settings">
          <summary>Repositories <.icon name="hero-chevron-down" class="size-3" /></summary>
          <div class="repository-settings-body">
            <p class="board-eyebrow">Track another repository</p>
            <form id="track-repo" phx-submit="add" class="flex flex-wrap items-center gap-2">
              <input
                name="owner"
                placeholder="owner"
                aria-label="Owner"
                class="w-20 border border-base-content/10 bg-base-200 px-3 py-2 text-sm sm:w-28"
              />
              <input
                name="name"
                placeholder="repo name"
                aria-label="Repository name"
                class="w-24 border border-base-content/10 bg-base-200 px-3 py-2 text-sm sm:w-36"
              />
              <button
                class="border border-base-content/10 px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary hover:bg-base-300"
                phx-disable-with="Tracking…"
              >Track repo</button>
            </form>
          </div>
        </details>
      </div>
      <div class="board-commandbar">
        <div class="board-health">
          <span
            id="connection-status"
            title="LiveView connection only; data freshness is shown separately"
            role="status"
            aria-live="polite"
            data-connected={to_string(@live)}
            phx-connected={JS.set_attribute({"data-connected", "true"})}
            phx-disconnected={JS.set_attribute({"data-connected", "false"})}
            class="text-xs"
          >
            <span class="connection-live text-success">live</span>
            <span class="connection-offline text-base-content/75">{if @live,
              do: "reconnecting",
              else: "static"}</span>
          </span>
          <span role="status" aria-live="polite">
            <button
              id="sync-status"
              type="button"
              aria-controls="panel-activity"
              phx-click="show_panel"
              phx-value-panel="activity"
              data-panel-trigger
              aria-haspopup="dialog"
              class={[
                "text-left text-xs underline underline-offset-4",
                @sync_event && has_errors?(@sync_event) && "sync-needs-attention",
                if(@sync_event && has_errors?(@sync_event),
                  do: "text-error",
                  else: "text-base-content/75"
                )
              ]}
            >
              {last_sync(@sync_event)}
            </button>
          </span>
          <span id="data-freshness" class="flex flex-wrap gap-x-4 gap-y-1">
            <DataAge.stamp
              id="sync-age"
              at={@sync_event && @sync_event.inserted_at}
              label={
                if @sync_event && @sync_event.kind == "sync_error",
                  do: "Last sync attempt",
                  else: "Last completed sync"
              }
              sync={@sync_event && @sync_event.kind == "sync"}
            />
            <span
              :if={@sync_event && @sync_event.kind == "sync_error"}
              class="text-[11px] text-warning"
            >Saved data age: unknown</span>
            <DataAge.stamp
              id="activity-age"
              at={@last_activity && @last_activity.inserted_at}
              label="Last activity"
            />
          </span>
        </div>
        <div class="board-utilities">
          <button
            phx-click="speak"
            class="border border-base-content/10 px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary hover:bg-base-300"
          >
            Speak status
          </button>
          <button
            phx-click="dictate"
            class="border border-base-content/10 px-3 py-2 text-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary hover:bg-base-300"
          >
            Dictate task
          </button>

          <Layouts.theme_toggle />
        </div>
      </div>
      <p
        id="voice-feedback"
        role="status"
        aria-live="polite"
        phx-update="ignore"
        class="w-full text-xs empty:hidden"
      >
      </p>
    </header>
    """
  end
end
