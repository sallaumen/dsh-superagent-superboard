defmodule AgentBoardWeb.BoardComponents.Activity do
  @moduledoc "The board's activity region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.Presentation

  alias AgentBoardWeb.BoardComponents.DataAge

  @impl true
  def render(assigns) do
    ~H"""
    <section id="activity" class="border-t border-base-content/10 px-5 py-4">
      <h3 class="py-2 text-xs uppercase tracking-[0.16em]">
        Atividade · últimos {length(@events)} eventos
      </h3>
      <p :if={@events == []} class="text-xs text-base-content/75">
        Nenhuma atividade registrada ainda.
      </p>
      <ol
        class="mt-3 max-h-64 space-y-2 overflow-y-auto"
        tabindex="0"
        aria-label="Atividade recente"
      >
        <li
          :for={e <- @events}
          class={[
            "grid min-w-0 gap-x-3 gap-y-1 text-xs sm:grid-cols-[10rem_10rem_minmax(0,1fr)]",
            has_errors?(e) && "text-error",
            warning?(e) && "text-warning"
          ]}
        >
          <DataAge.stamp id={"event-age-#{e.id}"} at={e.inserted_at} label="Registrado" />
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
    </section>
    """
  end
end
