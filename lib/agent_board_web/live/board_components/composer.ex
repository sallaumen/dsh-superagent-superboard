defmodule AgentBoardWeb.BoardComponents.Composer do
  @moduledoc """
  The request layer: write or dictate, split with review, then enqueue.

  The panel is a view of one explicit lifecycle owned by `BoardLive`: a
  draft, a job in flight (`splitting` or `enqueuing`), a proposal to review
  (`ready`, `needs_clarification`, `no_tasks`), a failure with a retry, and
  a receipt that names what was created. The receipt is read from the tasks
  the board stored, so a reload shows the same thing.

  Creating a task is a red action (`AgentBoard.Actions`): the sentence that
  confirms it, with the repository and the titles, sits above the send
  button (`confirm`), and the send passes it to the gate. A retry of the
  failures shows its own (`retry_confirm`).
  """
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1, kbd: 1]
  import AgentBoardWeb.BoardComponents.WorkTag, only: [work_tag: 1]
  import AgentBoardWeb.BoardComponents.ExecutorPicker, only: [executor_picker: 1]

  alias AgentBoard.Executors

  alias AgentBoard.Titles

  attr :repo, :string, required: true
  attr :text, :string, default: ""
  attr :title, :string, default: nil
  attr :split, :boolean, default: false
  attr :intake, :any, default: nil
  attr :selected, :any, default: nil
  attr :job, :any, default: nil
  attr :receipt, :any, default: nil
  attr :answers, :string, default: ""
  attr :ai_status, :any, default: :logged_in
  attr :voice_configured, :boolean, default: false
  attr :error, :string, default: nil
  attr :retry, :any, default: nil
  attr :confirm, :string, default: nil
  attr :retry_confirm, :string, default: nil
  attr :executor, :string, default: nil
  attr :suggestion, :map, default: nil

  def composer(assigns) do
    tasks = (assigns.intake && assigns.intake.tasks) || []
    status = assigns.intake && Map.get(assigns.intake, :status)
    spec = (assigns.intake && assigns.intake.spec) || %{}
    questions = spec["open_questions"] || []
    risks = spec["risks"] || []
    selected = assigns.selected || MapSet.new(Enum.to_list(0..max(length(tasks) - 1, 0)))

    assigns =
      assigns
      |> assign(:tasks, tasks)
      |> assign(:status, status)
      |> assign(:questions, questions)
      |> assign(:risks, risks)
      |> assign(:selected, selected)
      |> assign(:selected_count, Enum.count(selected, &(&1 in 0..max(length(tasks) - 1, 0))))
      |> assign(:derived_title, Titles.from_request(assigns.text))
      |> assign(:busy, not is_nil(assigns.job))
      |> assign(:step, step(assigns.receipt, status, assigns.job))

    ~H"""
    <div
      class="ab-compose"
      data-composer
      data-composer-state={state(@job, @receipt, @status, @error)}
    >
      <h2 id="composer-title" class="ab-sr">{gettext("New request")}</h2>

      <div class="ab-compose__head">
        <span class="ab-label">{if @split, do: gettext("Split request"), else: gettext("New request")} {gettext(
          "in"
        )}</span>
        <span class="ab-chip">{@repo}</span>
        <span class="ab-top__spacer"></span>
        <ol class="ab-steps" aria-label={gettext("Request stages")}>
          <li class={@step == 1 && "is-on"}><span>1</span>{gettext("Request")}</li>
          <li :if={@split} class={@step == 2 && "is-on"}><span>2</span>{gettext("Review")}</li>
          <li class={@step == 3 && "is-on"}>
            <span>{if @split, do: 3, else: 2}</span>{gettext("Receipt")}
          </li>
        </ol>
        <.kbd key="Esc" />
        <button
          type="button"
          class="ab-btn ab-btn--icon ab-btn--sm"
          phx-click="close"
          aria-label={gettext("Close (Esc)")}
        >
          <.ico name="close" />
        </button>
      </div>

      <.receipt :if={@receipt} receipt={@receipt} retry_confirm={@retry_confirm} />

      <form
        :if={is_nil(@receipt)}
        id="composer-form"
        phx-change="composer_change"
        phx-submit="composer_submit"
      >
        <p :if={@error} id="composer-error" class="ab-compose__error" role="alert">
          {@error}
          <button
            :if={@retry}
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet"
            phx-click="composer_retry"
            disabled={@busy}
          >
            {gettext("Try again")}
          </button>
          <span :if={@retry && @retry_confirm} class="ab-compose__retry-confirm">{@retry_confirm}</span>
        </p>

        <textarea
          id="composer-text"
          name="text"
          aria-label={gettext("Describe the request")}
          aria-describedby={@error && "composer-error"}
          placeholder={
            gettext("Describe what the agent should do. You can paste an issue, an error, or speak.")
          }
          phx-hook="Composer"
          autofocus
        >{@text}</textarea>

        <div :if={!@split and String.trim(@text) != ""} class="ab-compose__title">
          <label for="composer-issue-title" class="ab-label">{gettext("Issue title")}</label>
          <input
            id="composer-issue-title"
            name="title"
            type="text"
            maxlength="120"
            value={@title || @derived_title}
            aria-describedby="composer-title-hint"
          />
          <span id="composer-title-hint" class="ab-meta">
            {if @title,
              do: gettext("Edited by you."),
              else: gettext("From the request's first sentence; edit if you like.")}
          </span>
        </div>

        <p
          :if={@busy}
          id="composer-progress"
          class="ab-compose__progress"
          role="status"
          aria-live="polite"
        >
          <span class="ab-dot ab-dot--agent" aria-hidden="true"></span>
          {job_label(@job)}
          <button
            :if={@job.kind == :split}
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet"
            phx-click="composer_cancel"
          >
            {gettext("Cancel")}
          </button>
        </p>

        <div :if={@split && !is_nil(@intake) && !@busy} class="ab-sec__head ab-compose__split-head">
          <span class="ab-label">{split_head(@status, @tasks)}</span>
        </div>

        <div :if={@split && @status == :needs_clarification && !@busy} class="ab-split-note">
          <p :if={@questions != []} class="ab-meta">
            {gettext("The AI still has questions before splitting:")}
          </p>
          <ul :if={@questions != []}>
            <li :for={question <- @questions}>{question}</li>
          </ul>
          <p :if={@questions == [] and @risks != []} class="ab-meta">
            {gettext("The AI found the request ambiguous and highlighted these risks:")}
          </p>
          <ul :if={@questions == [] and @risks != []}>
            <li :for={risk <- @risks}>{risk}</li>
          </ul>
          <label for="composer-answers" class="ab-label">{gettext("Respond here")}</label>
          <textarea
            id="composer-answers"
            name="answers"
            rows="3"
            placeholder={
              gettext("Your answers are added to the request before the AI splits it again.")
            }
          >{@answers}</textarea>
          <p class="ab-meta">{gettext("Or edit the request above and split again.")}</p>
        </div>

        <div :if={@split && @status == :no_tasks && !@busy} class="ab-split-note">
          <p class="ab-meta">
            {gettext(
              "The AI did not propose any usable task for this request. Try again or submit as a single request."
            )}
          </p>
          <button type="button" class="ab-btn ab-btn--sm" phx-click="composer_single">
            {gettext("Send as a single request")}
          </button>
        </div>

        <.executor_picker
          :if={@executor && String.trim(@text) != ""}
          chosen={@executor}
          suggestion={@suggestion}
          disabled={@busy}
        />

        <div :if={@split && @tasks != [] && !@busy} class="ab-split">
          <input type="hidden" name="tasks[]" value="" />
          <label
            :for={{task, index} <- Enum.with_index(@tasks)}
            for={"composer-task-#{index}"}
            class="ab-split__item"
          >
            <input
              type="checkbox"
              id={"composer-task-#{index}"}
              name="tasks[]"
              value={index}
              checked={index in @selected}
              class="ab-sr"
            />
            <span
              class={"ab-check" <> if(index in @selected, do: " is-on", else: "")}
              aria-hidden="true"
            ></span>
            <span class="ab-row__pos">{index + 1}</span>
            <span>{task.title}</span>
            <.work_tag work_type={task.kind} size={task.size} />
          </label>
        </div>

        <p :if={@confirm && !@busy} id="composer-confirm" class="ab-compose__confirm">
          {@confirm}
        </p>

        <div class="ab-compose__bar">
          <button
            type="button"
            class="ab-btn ab-btn--icon ab-btn--sm"
            aria-label={gettext("Dictate by voice")}
            phx-click={JS.dispatch("board:voice-start")}
            disabled={not @voice_configured or @busy}
            title={
              if @voice_configured,
                do: gettext("Dictate by voice"),
                else: gettext("Transcription is not configured")
            }
          >
            <.ico name="mic" />
          </button>

          <span id="composer-voice" class="ab-voice" data-phase="idle" hidden>
            <span class="ab-level" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i></span>
            <span data-voice-label>{gettext("Listening...")}</span>
            <button
              type="button"
              class="ab-btn ab-btn--icon ab-btn--sm ab-btn--quiet"
              aria-label={gettext("Stop listening")}
              phx-click={JS.dispatch("board:voice-stop")}
            >
              <.ico name="stop" />
            </button>
          </span>

          <button
            type="button"
            class="ab-toggle"
            role="switch"
            aria-checked={to_string(@split)}
            phx-click="composer_split"
            disabled={@ai_status == :not_configured or @busy}
            title={
              if @ai_status == :not_configured,
                do: gettext("AI is not configured"),
                else: gettext("Split into tasks")
            }
          >
            <span class="ab-toggle__track"></span>{gettext("Split into tasks")}
          </button>

          <span class="ab-top__spacer"></span>

          <button
            class="ab-btn ab-btn--primary"
            phx-disable-with={disable_label(@split, @status)}
            disabled={submit_disabled?(@text, @split, @status, @selected_count, @busy)}
          >
            {button_label(@split, @status, @selected_count)}<.kbd key="⌘↵" />
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp step(receipt, _status, _job) when not is_nil(receipt), do: 3

  defp step(_receipt, status, _job) when status in [:ready, :needs_clarification, :no_tasks],
    do: 2

  defp step(_receipt, _status, _job), do: 1

  attr :receipt, :map, required: true
  attr :retry_confirm, :string, default: nil

  defp receipt(assigns) do
    created = Enum.count(assigns.receipt.items, &(&1.outcome == :created))
    existing = Enum.count(assigns.receipt.items, &(&1.outcome == :existing))
    failed = Enum.count(assigns.receipt.items, &match?({:error, _}, &1.outcome))

    assigns =
      assigns
      |> assign(:failed, failed)
      |> assign(:head, receipt_head(created, existing, failed))

    ~H"""
    <section id="composer-receipt" class="ab-receipt" role="status" aria-live="polite">
      <p class={["ab-receipt__head", @failed > 0 && "is-halt"]}>{@head}</p>
      <ul class="ab-receipt__list">
        <li :for={item <- @receipt.items} class="ab-receipt__item">
          <span class="ab-need__id">{receipt_number(item)}</span>
          <span class="ab-receipt__title">
            {item.title}
            <.work_tag :if={item.task} work_type={item.task.work_type} size={item.task.size} />
            <span :if={item.task && item.task.executor} class="ab-meta ab-receipt__exec">
              {Executors.name(item.task.executor)}
            </span>
          </span>
          <span class={["ab-tag", outcome_class(item.outcome)]}>{outcome_label(item.outcome)}</span>
          <span :if={item.task} class="ab-receipt__links">
            <a
              :if={item.task.url}
              class="ab-btn ab-btn--sm ab-btn--quiet"
              href={item.task.url}
              target="_blank"
              rel="noopener noreferrer"
            >
              {gettext("Open issue")}<span class="ab-sr">{gettext("(opens GitHub in a new tab)")}</span>
            </a>
            <button
              type="button"
              class="ab-btn ab-btn--sm ab-btn--quiet"
              phx-click="open"
              phx-value-id={item.task.id}
            >
              {gettext("View on board")}
            </button>
          </span>
        </li>
      </ul>
      <p :if={@failed > 0 && @retry_confirm} id="composer-retry-confirm" class="ab-compose__confirm">
        {@retry_confirm}
      </p>
      <div class="ab-receipt__actions">
        <button
          :if={@failed > 0}
          type="button"
          class="ab-btn ab-btn--sm ab-btn--primary"
          phx-click="composer_retry"
        >
          {gettext("Retry the %{count} failed tasks", count: @failed)}
        </button>
        <button type="button" class="ab-btn ab-btn--sm" phx-click="composer_reset">
          {gettext("New request")}
        </button>
        <button type="button" class="ab-btn ab-btn--sm ab-btn--quiet" phx-click="close">
          {gettext("Close")}
        </button>
      </div>
    </section>
    """
  end

  defp receipt_head(0, 0, failed),
    do: ngettext("Nothing queued: %{count} failed.", "Nothing queued: %{count} failed.", failed)

  defp receipt_head(created, existing, 0) do
    [
      created > 0 && ngettext("%{count} request queued", "%{count} requests queued", created),
      existing > 0 &&
        ngettext("%{count} was already queued", "%{count} were already queued", existing)
    ]
    |> Enum.filter(& &1)
    |> Enum.join("; ")
    |> Kernel.<>(".")
  end

  defp receipt_head(created, existing, failed) do
    done = created + existing

    gettext("%{done} of %{total} queued; %{failed} failed.",
      done: done,
      total: done + failed,
      failed: failed
    )
  end

  defp receipt_number(%{task: %{number: number}}) when is_integer(number), do: "##{number}"
  defp receipt_number(_item), do: "—"

  defp outcome_label(:created), do: gettext("queued")
  defp outcome_label(:existing), do: gettext("Already in the queue")
  defp outcome_label({:error, reason}), do: gettext("failed: ") <> failure_reason(reason)

  defp outcome_class(:created), do: "ab-tag--agent"
  defp outcome_class(:existing), do: nil
  defp outcome_class({:error, _}), do: "ab-tag--halt"

  @doc "The human reason for a failed creation."
  def failure_reason(:conflict), do: gettext("The issue already existed with another number")

  def failure_reason(:dependency_failed),
    do: gettext("A task it depends on was not created; try again")

  def failure_reason(reason), do: AgentBoardWeb.FailureText.text(reason)

  defp state(job, _receipt, _status, _error) when not is_nil(job), do: to_string(job.kind)
  defp state(_job, receipt, _status, _error) when not is_nil(receipt), do: "receipt"
  defp state(_job, _receipt, _status, error) when not is_nil(error), do: "failed"
  defp state(_job, _receipt, nil, _error), do: "draft"
  defp state(_job, _receipt, status, _error), do: to_string(status)

  defp job_label(%{kind: :split}), do: gettext("Splitting the request into tasks with AI…")
  defp job_label(%{kind: :enqueue, total: 1}), do: gettext("Creating the issue on GitHub…")

  defp job_label(%{kind: :enqueue, total: n}),
    do: gettext("Creating %{count} issues on GitHub…", count: n)

  defp job_label(_job), do: gettext("Working…")

  defp split_head(:ready, tasks),
    do: gettext("This will become %{count} tasks, in this order", count: length(tasks))

  defp split_head(:needs_clarification, _tasks), do: gettext("AI needs answers before splitting")
  defp split_head(:no_tasks, _tasks), do: gettext("AI did not propose tasks")
  defp split_head(_status, _tasks), do: ""

  defp submit_disabled?(_text, _split, _status, _count, true), do: true
  defp submit_disabled?(text, false, _status, _count, _busy), do: String.trim(text) == ""
  defp submit_disabled?(text, true, nil, _count, _busy), do: String.trim(text) == ""
  defp submit_disabled?(_text, true, :ready, count, _busy), do: count == 0
  defp submit_disabled?(_text, true, _status, _count, _busy), do: false

  defp button_label(false, _status, _count), do: gettext("Add to queue")
  defp button_label(true, :ready, count), do: gettext("Queue %{count}", count: count)
  defp button_label(true, :needs_clarification, _count), do: gettext("Split with answers")
  defp button_label(true, _status, _count), do: gettext("Split request")

  defp disable_label(false, _status), do: gettext("Sending…")
  defp disable_label(true, :ready), do: gettext("Sending…")
  defp disable_label(true, _status), do: gettext("Splitting…")
end
