defmodule AgentBoardWeb.BoardComponents.Header do
  @moduledoc "The board's header region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation

  @impl true
  def render(assigns) do
    ~H"""
    <header
      id={@id}
      class="flex flex-wrap items-center gap-3 border-b border-base-content/10 px-5 py-3"
    >
      <div class="flex flex-wrap items-baseline gap-2">
        <h1 class="text-lg tracking-[0.16em] uppercase">Agent board</h1>
        <span class="text-[10px] text-base-content/75">the agent's work, live</span>
      </div>

      <form id="repo-select" phx-change="select" class="contents">
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

      <span class="flex-1"></span>

      <span
        id="connection-status"
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
          aria-controls="activity"
          phx-click={
            JS.set_attribute({"open", ""}, to: "#activity") |> JS.focus(to: "#activity summary")
          }
          class={[
            "text-left text-xs underline underline-offset-4",
            if(@sync_event && has_errors?(@sync_event),
              do: "text-error",
              else: "text-base-content/75"
            )
          ]}
        >
          {last_sync(@sync_event)}
        </button>
      </span>

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
