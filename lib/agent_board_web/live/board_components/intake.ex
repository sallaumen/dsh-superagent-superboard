defmodule AgentBoardWeb.BoardComponents.Intake do
  @moduledoc "The board's intake region. Events are handled by BoardLive."
  use AgentBoardWeb, :live_component

  import AgentBoardWeb.BoardComponents.WorkTag, only: [work_tag: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="border-t border-base-content/10 px-5 py-4">
      <p id="intake-repository" class="mb-4 text-xs text-base-content/75 sm:text-right">
        {gettext("Repository")}
        <strong class="font-semibold text-base-content">{@repo.owner}/{@repo.name}</strong>
      </p>

      <p
        :if={@draft && @draft.source == :voice}
        id="intake-voice-draft"
        class="mb-4 border-l-2 border-l-info bg-info/10 px-3 py-2 text-xs leading-relaxed text-base-content"
      >
        {gettext("Voice draft. Review the text and repository before splitting.")}
      </p>

      <p
        :if={@ai_status == :not_configured}
        id="intake-unavailable"
        class="mb-3 text-xs text-base-content/75"
      >
        {gettext("AI not configured. Split is unavailable until a model is configured.")}
      </p>
      <form id="intake-form" phx-submit="intake" phx-change="intake_draft_change" class="space-y-3">
        <label for="intake-request" class="block text-xs font-semibold text-base-content">
          {gettext("Request")}
        </label>
        <textarea
          id="intake-request"
          name="text"
          rows="4"
          placeholder={gettext("Describe what you want the agent to build…")}
          aria-describedby={if @ai_status == :not_configured, do: "intake-unavailable"}
          class="min-h-28 w-full resize-y rounded-sm border border-(--line-strong) bg-(--surface) px-3 py-2.5 text-sm leading-relaxed text-base-content focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
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
            {gettext("Split proposes tasks. Does not create issues.")}
          </p>
          <button
            disabled={@ai_status == :not_configured}
            phx-disable-with={gettext("Splitting...")}
            class="ab-btn ab-btn--primary min-h-10"
          >
            {gettext("Split request")}
          </button>
        </div>
      </form>

      <div :if={@intake} class="mt-4">
        <p
          :if={@intake.status == :needs_clarification}
          id="intake-needs-clarification"
          role="status"
          class="mb-3 border-l-2 border-l-warning bg-warning/10 px-3 py-2 text-xs leading-relaxed text-base-content"
        >
          {gettext("This request needs more detail before proposing tasks.")}
          <%= if @intake.spec["open_questions"] != [] do %>
            {gettext("Review the questions below and edit the request.")}
          <% else %>
            {gettext("Add detail and try again.")}
          <% end %>
        </p>
        <p
          :if={@intake.status == :no_tasks}
          id="intake-no-tasks"
          role="status"
          class="mb-3 border-l-2 border-l-warning bg-warning/10 px-3 py-2 text-xs leading-relaxed text-base-content"
        >
          {gettext("No usable task was proposed. Review the request and try splitting it again.")}
        </p>
        <p class="text-xs font-semibold text-base-content/75">{gettext("Objective")}</p>
        <p class="text-sm text-base-content">{@intake.spec["goal"]}</p>

        <div :if={@intake.spec["open_questions"] != []} class="mt-2 text-xs text-warning">
          <p class="font-semibold">{gettext("Open questions")}</p>
          <p :for={q <- @intake.spec["open_questions"]}>{q}</p>
        </div>

        <ol class="mt-3 space-y-2">
          <li
            :for={{task, index} <- Enum.with_index(@intake.tasks)}
            class="border border-base-content/10 border-l-2 border-l-info bg-base-200 px-3 py-2"
          >
            <p class="text-[13px]">
              {task.title}
              <.work_tag
                work_type={task.kind}
                size={task.size}
                class="ml-2 text-xs text-base-content/75"
              />
            </p>
            <p class="mt-1 text-xs text-base-content/75">{task.body}</p>
            <%!-- Creating is red (AgentBoard.Actions): the browser asks the
                 sentence, and the click carries it to the gate. --%>
            <button
              phx-click="create_from_intake"
              phx-disable-with={gettext("Creating…")}
              phx-value-index={index}
              phx-value-confirm={Enum.at(@phrases, index)}
              data-confirm={Enum.at(@phrases, index)}
              class="ab-btn ab-btn--sm mt-2"
            >
              {gettext("Create")}
            </button>
          </li>
        </ol>
      </div>
    </section>
    """
  end
end
