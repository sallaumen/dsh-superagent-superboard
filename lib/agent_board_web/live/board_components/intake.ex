defmodule AgentBoardWeb.BoardComponents.Intake do
  @moduledoc "The board's intake region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="border-t border-base-content/10 px-5 py-4">
      <p id="intake-repository" class="mb-4 text-xs text-base-content/75 sm:text-right">
        Repository <strong class="font-semibold text-base-content">{@repo.owner}/{@repo.name}</strong>
      </p>

      <p
        :if={@draft && @draft.source == :voice}
        id="intake-voice-draft"
        class="mb-4 border-l-2 border-l-info bg-info/10 px-3 py-2 text-xs leading-relaxed text-base-content"
      >
        Voice draft. Review the wording and repository before splitting.
      </p>

      <p
        :if={@ai_status == :not_configured}
        id="intake-unavailable"
        class="mb-3 text-xs text-base-content/75"
      >
        AI is not configured. Split is unavailable until a model is configured.
      </p>
      <form id="intake-form" phx-submit="intake" phx-change="intake_draft_change" class="space-y-3">
        <label for="intake-request" class="block text-xs font-semibold text-base-content">
          Request
        </label>
        <textarea
          id="intake-request"
          name="text"
          rows="4"
          placeholder="Describe what you want the agent to build…"
          aria-describedby={if @ai_status == :not_configured, do: "intake-unavailable"}
          phx-debounce="300"
          class="min-h-28 w-full resize-y rounded-lg border border-base-content/20 bg-base-200 px-3 py-2.5 text-sm leading-relaxed text-base-content focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          required
        >{@draft && @draft.text}</textarea>
        <input
          :if={@draft && @draft.source == :voice}
          type="hidden"
          name="source_repo"
          value={@draft.repo_id}
        />
        <div class="flex flex-wrap items-center justify-between gap-3">
          <p class="max-w-sm text-xs leading-relaxed text-base-content/75">
            Split proposes tasks. It does not create issues.
          </p>
          <button
            disabled={@ai_status == :not_configured}
            phx-disable-with="Splitting…"
            class="min-h-11 rounded-lg bg-primary px-4 py-2 text-sm font-bold text-primary-content hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            Split request
          </button>
        </div>
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
