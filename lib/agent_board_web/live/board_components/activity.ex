defmodule AgentBoardWeb.BoardComponents.Activity do
  @moduledoc "The board's activity region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation

  @impl true
  def render(assigns) do
    ~H"""
    <details id="activity" class="border-t border-base-content/10 px-5 py-4">
      <summary class="cursor-pointer py-2 text-xs uppercase tracking-[0.16em]">
        Activity · latest {length(@events)} events
      </summary>
      <ol
        class="mt-3 max-h-64 space-y-2 overflow-y-auto"
        tabindex="0"
        aria-label="Recent activity"
      >
        <li
          :for={e <- @events}
          class={[
            "grid min-w-0 gap-x-3 gap-y-1 text-xs sm:grid-cols-[5rem_10rem_minmax(0,1fr)]",
            has_errors?(e) && "text-error",
            warning?(e) && "text-warning"
          ]}
        >
          <span class="w-24 shrink-0 text-base-content/75">{time(e.inserted_at)}</span>
          <span class="break-words uppercase">{e.kind}</span>
          <span class="min-w-0 break-words text-base-content">{e.subject}</span>
          <span
            :if={e.payload && e.payload != %{}}
            class="min-w-0 break-words text-base-content/75 sm:col-span-2 sm:col-start-2"
          >
            {payload_summary(e.payload)}
          </span>
        </li>
      </ol>
    </details>
    """
  end
end
