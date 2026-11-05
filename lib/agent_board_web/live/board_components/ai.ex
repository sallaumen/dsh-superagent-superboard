defmodule AgentBoardWeb.BoardComponents.AI do
  @moduledoc "The board's ai region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="border-t border-base-content/10 px-5 py-4">
      <h2 class="mb-3 flex items-center gap-3 text-[11px] uppercase tracking-[0.16em] text-base-content/75">
        <span>AI · all repositories</span>
        <span class={["text-[10px] normal-case", @ai_status != :logged_in && "text-warning"]}>
          {ai_status_label(@ai_status)}
        </span>
      </h2>
      <p :if={@ai_calls == []} class="text-xs text-base-content/75">No AI calls recorded yet.</p>
      <p :if={@ai_calls != []} class="mb-2 text-xs text-base-content/75">
        Latest {length(@ai_calls)} calls across the board.
      </p>
      <ol class="space-y-1">
        <li :for={c <- @ai_calls} class="flex flex-wrap gap-x-3 gap-y-1 text-xs">
          <span class="min-w-0 break-words uppercase">{c.name}</span>
          <span class="w-20 shrink-0 text-base-content/75">{c.engine}</span>
          <span class={["w-16 shrink-0", c.status == "error" && "text-error"]}>
            {c.status}
          </span>
          <span class="w-20 shrink-0 text-base-content/75">{c.duration_ms}ms</span>
          <span class="text-base-content/75">{c.input_tokens + c.output_tokens} tokens</span>
        </li>
      </ol>
    </section>
    """
  end
end
