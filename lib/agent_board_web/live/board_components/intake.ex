defmodule AgentBoardWeb.BoardComponents.Intake do
  @moduledoc "The board's intake region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="border-t border-base-content/10 px-5 py-4">
      <h2 class="mb-3 text-[11px] uppercase tracking-[0.16em] text-base-content/75">
        Split a request
      </h2>

      <p
        :if={@ai_status == :not_configured}
        id="intake-unavailable"
        class="mb-3 text-xs text-base-content/75"
      >
        AI is not configured. Split is unavailable until a model is configured.
      </p>
      <form id="intake-form" phx-submit="intake" class="flex gap-2">
        <input
          name="text"
          placeholder="Describe what you want..."
          aria-label="Request"
          disabled={@ai_status == :not_configured}
          aria-describedby={if @ai_status == :not_configured, do: "intake-unavailable"}
          class="flex-1 border border-base-content/10 bg-base-200 px-3 py-2 text-sm"
          required
        />
        <button
          disabled={@ai_status == :not_configured}
          phx-disable-with="Splitting…"
          class="bg-primary px-4 py-2 text-sm font-bold text-primary-content hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          Split
        </button>
      </form>

      <div :if={@intake} class="mt-4">
        <p class="text-[10px] uppercase text-base-content/75">Goal</p>
        <p class="text-sm text-base-content">{@intake.spec["goal"]}</p>

        <div :if={@intake.spec["open_questions"] != []} class="mt-2 text-[11px] text-warning">
          <p class="uppercase text-[10px]">Open questions</p>
          <p :for={q <- @intake.spec["open_questions"]}>{q}</p>
        </div>

        <ol class="mt-3 space-y-2">
          <li
            :for={{task, index} <- Enum.with_index(@intake.tasks)}
            class="border border-base-content/10 border-l-2 border-l-info bg-base-200 px-3 py-2"
          >
            <p class="text-[13px]">
              {task.title}
              <span class="ml-2 text-[10px] uppercase text-base-content/75">{task.kind}</span>
              <span class="ml-2 text-[10px] uppercase text-base-content/75">{task.size}</span>
            </p>
            <p class="mt-1 text-[11px] text-base-content/75">{task.body}</p>
            <button
              phx-click="create_from_intake"
              phx-disable-with="Creating…"
              phx-value-index={index}
              class="mt-2 border border-base-content/10 px-2 py-1 text-[10px]"
            >
              Create
            </button>
          </li>
        </ol>
      </div>
    </section>
    """
  end
end
