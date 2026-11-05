defmodule AgentBoardWeb.BoardComponents.Conversation do
  @moduledoc "The board's conversation region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  alias AgentBoardWeb.BoardComponents.DataAge

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id="conversation"
      class="border-t border-base-content/10 px-5 py-4"
    >
      <h2
        id="conversation-title"
        tabindex="-1"
        class="mb-3 flex flex-wrap items-center gap-3 text-[11px] uppercase tracking-[0.16em] text-base-content/75"
      >
        <span>Conversation · #{@conversation.number} {@conversation.title}</span>
        <button phx-click="speak" class="border border-base-content/10 px-2 py-1 text-[10px]">
          Speak board status
        </button>
      </h2>

      <p class="mb-3 whitespace-pre-wrap break-words text-sm">
        {@conversation.body || "No task details recorded."}
      </p>
      <div class="mb-3">
        <DataAge.stamp id="conversation-age" at={@conversation.updated_at} label="Record updated" />
      </div>

      <div :for={c <- @comments} class="mb-2 flex gap-2">
        <span class={[
          "w-10 shrink-0 text-[10px] uppercase sm:w-14",
          c.kind == "agent" && "text-success",
          c.kind != "agent" && "text-info"
        ]}>
          {c.kind}
        </span>
        <div class="min-w-0">
          <p class="whitespace-pre-wrap break-words text-[12px] leading-relaxed text-base-content">
            {c.body}
          </p>
          <DataAge.stamp id={"comment-age-#{c.id}"} at={c.inserted_at} label="Posted" />
        </div>
      </div>

      <p :if={@comments == []} class="text-xs text-base-content/75">
        No messages yet. Ask the agent below.
      </p>

      <form id="ask-agent" phx-submit="ask" class="mt-3 flex gap-2">
        <input
          id="ask-body"
          name="body"
          aria-label="Message to the agent"
          placeholder="Ask the agent…"
          class="flex-1 border border-base-content/10 bg-base-200 px-3 py-2 text-sm"
          required
        />
        <button
          class="bg-primary px-4 py-2 text-sm font-bold text-primary-content hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          phx-disable-with="Sending…"
        >Send</button>
      </form>
    </section>
    """
  end
end
