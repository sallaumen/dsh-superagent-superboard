defmodule AgentBoardWeb.BoardComponents.Composer do
  @moduledoc """
  The request layer: write or dictate, split with review, then enqueue.

  The panel is a view of one explicit lifecycle on `BoardLive`'s socket,
  `AgentBoardWeb.ComposerLifecycle`: a
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

  alias AgentBoard.{Executors, Intake, Titles}
  alias AgentBoard.Intake.Clarifications
  alias AgentBoardWeb.BoardComponents.PrivatePanel

  attr :repo, :string, required: true
  attr :text, :string, default: ""
  attr :title, :string, default: nil
  attr :split, :boolean, default: false
  attr :max_tasks, :integer, default: nil
  attr :intake, :any, default: nil
  attr :uploads, :map, default: nil
  attr :attachments_ready, :integer, default: 0

  attr :private, :map,
    default: %{note: "", folder: "", folders: [], folder_error: nil, meta: %{}, files: []}

  attr :selected, :any, default: nil
  attr :job, :any, default: nil
  attr :receipt, :any, default: nil
  attr :maintenance_path, :string, default: nil
  attr :answers, :map, default: %{}
  attr :ai_status, :any, default: :logged_in
  attr :voice_configured, :boolean, default: false
  attr :error, :string, default: nil
  attr :retry, :any, default: nil
  attr :confirm, :string, default: nil
  attr :retry_confirm, :string, default: nil
  attr :executor, :string, default: nil
  attr :suggestion, :map, default: nil

  def composer(assigns) do
    intake = assigns.intake || %{}
    tasks = Map.get(intake, :tasks, [])
    status = intake[:status]
    spec = Map.get(intake, :spec, %{})
    questions = Clarifications.questions(spec)
    risks = spec["risks"] || []
    selected = assigns.selected || MapSet.new(Enum.to_list(0..max(length(tasks) - 1, 0)))

    assigns =
      assigns
      |> assign(:tasks, tasks)
      |> assign(:status, status)
      |> assign(:clarifications, Map.get(intake, :history, []))
      |> assign(:questions, questions)
      |> assign(:spec, spec)
      |> assign(:incomplete, incomplete?(tasks, selected))
      |> assign(:risks, risks)
      |> assign(:selected, selected)
      |> assign(:selected_count, Enum.count(selected, &(&1 in 0..max(length(tasks) - 1, 0))))
      |> assign(:derived_title, Titles.from_request(assigns.text))
      |> assign(:busy, not is_nil(assigns.job))
      |> assign(:attachment_entries, attachment_entries(assigns.uploads))
      |> assign(:attachments_pending, attachments_pending?(assigns.uploads))
      |> assign(:step, step(assigns.receipt, status, assigns.job))

    ~H"""
    <div
      class="ab-compose"
      data-composer
      data-composer-state={state(@job, @receipt, @status, @error)}
    >
      <h2 id="composer-title" class="ab-sr">{gettext("New request")}</h2>

      <div class="ab-compose__head">
        <span class="ab-label">{if @split,
          do: gettext("Split request in"),
          else: gettext("New request in")}</span>
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

      <.receipt
        :if={@receipt}
        receipt={@receipt}
        retry_confirm={@retry_confirm}
        maintenance_path={@maintenance_path}
      />

      <form
        :if={is_nil(@receipt)}
        id="composer-form"
        phx-change="composer_change"
        phx-submit={
          if @status == :needs_clarification, do: "composer_answer", else: "composer_submit"
        }
      >
        <div class="ab-compose__fields">
          <p :if={@error} id="composer-error" class="ab-compose__error" role="alert">
            {@error}
            <span :if={@status == :ready && match?({:split, _}, @retry)}>{gettext(
              "Your previous proposal and edits are still available."
            )}</span>
            <button
              :if={@retry && @status != :needs_clarification}
              type="button"
              class="ab-btn ab-btn--sm ab-btn--quiet"
              phx-click="composer_retry"
              disabled={@busy}
            >
              {if match?({:split, _}, @retry),
                do: gettext("Retry with AI"),
                else: gettext("Try again")}
            </button>
            <span :if={@retry && @retry_confirm} class="ab-compose__retry-confirm">{@retry_confirm}</span>
          </p>

          <p :if={!@busy} id="composer-draft-state" class="ab-compose__draft">
            <strong>{gettext("Draft")}</strong>
            {gettext("Editing this draft does not change GitHub.")}
          </p>
          <textarea
            id="composer-text"
            name="text"
            aria-label={gettext("Describe the request")}
            aria-describedby={@error && "composer-error"}
            placeholder={
              gettext(
                "Describe what the agent should do. You can paste an issue, an error, or speak."
              )
            }
            phx-hook="Composer"
            autofocus
          >{@text}</textarea>

          <div
            :if={
              @ai_status != :not_configured && String.trim(@text) != "" &&
                @status != :needs_clarification
            }
            class="ab-compose__limit"
          >
            <label for="composer-max-tasks">{gettext("Maximum tasks per split")}</label>
            <select id="composer-max-tasks" name="max_tasks" disabled={@busy}>
              <option value="" selected={is_nil(@max_tasks)}>{gettext("Automatic")}</option>
              <option :for={limit <- Intake.limits()} value={limit} selected={limit == @max_tasks}>
                {limit}
              </option>
            </select>
          </div>

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

          <div
            :if={@split && !is_nil(@intake) && @status != :needs_clarification && !@busy}
            id="composer-proposal-status"
            tabindex="-1"
            phx-mounted={JS.focus()}
            class="ab-sec__head ab-compose__split-head"
            role="status"
          >
            <span class="ab-label">{split_head(@status, @tasks)}</span>
          </div>

          <section
            :if={@split && @status == :needs_clarification && !@busy}
            class="ab-questions"
            aria-labelledby={"composer-required-title-#{@intake.round}"}
          >
            <input type="hidden" name="round" value={@intake.round} />
            <h3 id={"composer-required-title-#{@intake.round}"} tabindex="-1" phx-mounted={JS.focus()}>
              {gettext("Clarify the request")}
            </h3>
            <p id="composer-answer-help" class="ab-meta">
              {if @spec["blocking_questions"] in [nil, []],
                do:
                  gettext(
                    "Answer at least one question. AI will use the question and answer together to prepare a draft."
                  ),
                else: gettext("Answer each question. AI will use these pairs to prepare a draft.")}
            </p>
            <p
              :if={
                @spec["blocking_questions"] in [nil, []] and @spec["open_questions"] in [nil, []] and
                  @risks != []
              }
              class="ab-meta"
            >
              {Enum.join(@risks, " · ")}
            </p>
            <.question_fields
              questions={@questions}
              answers={@answers}
              group="clarify"
              prefix="clarify"
              help="composer-answer-help"
            />
          </section>

          <details
            :if={@clarifications != [] && @status == :ready && !@busy}
            id="composer-applied"
            phx-mounted={JS.ignore_attributes(["open"])}
            class="ab-questions ab-questions--applied"
          >
            <summary>{gettext("Answers used in this proposal")} · {length(@clarifications)}</summary>
            <dl>
              <div :for={{q, a} <- @clarifications}>
                <dt>{q}</dt><dd>{a}</dd>
              </div>
            </dl>
          </details>

          <p :if={@split && @status == :no_tasks && !@busy} class="ab-split-note">
            {gettext("No tasks to review. Ask AI again or return to a single issue draft.")}
          </p>

          <p
            :if={@split && !@busy && Intake.over_limit?(length(@tasks), @max_tasks)}
            id="composer-split-limit-note"
            class="ab-split-note"
            role="status"
          >
            {gettext("AI proposed %{total} tasks. Select up to %{limit}, or split again.",
              total: length(@tasks),
              limit: @max_tasks
            )}
          </p>

          <.understood :if={@split && @status == :ready && !@busy} spec={@spec} />

          <div :if={@split && @tasks != [] && !@busy} class="ab-split">
            <input type="hidden" name="tasks[]" value="" />
            <div :for={{task, index} <- Enum.with_index(@tasks)} class="ab-split__task">
              <label for={"composer-task-#{index}"} class="ab-split__item">
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
              <p id={"composer-task-deps-#{index}"} class="ab-meta ab-split__deps">
                {dependency_label(Intake.dependencies_within(@tasks, index, @selected))}
              </p>
              <details
                id={"composer-task-detail-#{index}"}
                class="ab-split__detail"
                phx-mounted={JS.ignore_attributes(["open"])}
              >
                <summary>{gettext("Edit title, description and acceptance")}</summary>
                <label for={"composer-task-title-#{index}"} class="ab-label">{gettext("Title")}</label>
                <input
                  id={"composer-task-title-#{index}"}
                  name={"task_edits[#{index}][title]"}
                  type="text"
                  maxlength="255"
                  value={task.title}
                />
                <label for={"composer-task-body-#{index}"} class="ab-label">
                  {gettext("Description")}
                </label>
                <textarea
                  id={"composer-task-body-#{index}"}
                  name={"task_edits[#{index}][body]"}
                  rows="6"
                >{task.body}</textarea>
                <label for={"composer-task-acceptance-#{index}"} class="ab-label">
                  {gettext("Acceptance criteria, one per line")}
                </label>
                <textarea
                  id={"composer-task-acceptance-#{index}"}
                  name={"task_edits[#{index}][acceptance]"}
                  rows="4"
                >{Enum.join(task.acceptance, "\n")}</textarea>
              </details>
              <div class="ab-split__detail">
                <label for={"composer-proof-#{index}"} class="ab-label">{gettext("How to verify")}</label>
                <textarea
                  id={"composer-proof-#{index}"}
                  name={"task_edits[#{index}][verification]"}
                  rows="3"
                >{Map.get(task, :verification, "")}</textarea>
                <fieldset :if={Map.get(task, :guides, []) != []} class="ab-split__guides">
                  <legend class="ab-label">{gettext("Include guides in this issue")}</legend>
                  <input type="hidden" name={"task_edits[#{index}][guides][]"} value="" />
                  <label :for={guide <- task.guides} class="ab-attach__opt">
                    <input
                      type="checkbox"
                      name={"task_edits[#{index}][guides][]"}
                      value={guide.id}
                      checked={guide.id in task.selected_guides}
                    />
                    <span>{guide.id}</span>
                    <span :if={guide.scope == :local} class="ab-meta">{gettext("On this computer")}</span>
                  </label>
                </fieldset>
              </div>
            </div>
          </div>

          <p
            :if={@incomplete && !@busy}
            id="composer-incomplete"
            class="ab-compose__confirm"
            role="status"
          >
            {gettext("Every chosen task needs a title, a description and a criterion.")}
          </p>

          <section
            :if={@attachment_entries != [] or @attachments_ready > 0}
            id="composer-attachments"
            class="ab-attach"
            aria-label={gettext("Attached files")}
          >
            <p :if={@attachments_ready > 0} class="ab-meta">
              {gettext("%{count} files ready to send", count: @attachments_ready)}
            </p>
            <div :for={entry <- @attachment_entries} class="ab-attach__item">
              <.live_img_preview :if={image?(entry)} entry={entry} class="ab-attach__thumb" alt="" />
              <span class="ab-attach__name">{entry.client_name}</span>
              <span class="ab-meta">{entry_status(entry, @uploads)}</span>
              <label class="ab-attach__opt">
                <span class="ab-sr">{gettext("Role of %{name}", name: entry.client_name)}</span>
                <select name={"attachment_meta[#{entry.ref}][role]"}>
                  <option
                    :for={{value, label} <- roles()}
                    value={value}
                    selected={meta(@private, entry.ref).role == value}
                  >
                    {label}
                  </option>
                </select>
              </label>
              <label class="ab-attach__opt">
                <input type="hidden" name={"attachment_meta[#{entry.ref}][private]"} value="false" />
                <input
                  type="checkbox"
                  name={"attachment_meta[#{entry.ref}][private]"}
                  value="true"
                  checked={meta(@private, entry.ref).private}
                />
                {gettext("Only on this machine")}
              </label>
              <button
                type="button"
                class="ab-btn ab-btn--icon ab-btn--sm ab-btn--quiet"
                phx-click="composer_remove_attachment"
                phx-value-ref={entry.ref}
                aria-label={gettext("Remove %{name}", name: entry.client_name)}
              >
                <.ico name="close" />
              </button>
            </div>
            <p :for={error <- upload_level_errors(@uploads)} class="ab-compose__error" role="alert">
              {error}
            </p>
          </section>

          <.executor_picker
            :if={@executor && String.trim(@text) != "" && @status != :needs_clarification && !@busy}
            chosen={@executor}
            suggestion={@suggestion}
            disabled={@busy}
          />

          <details
            :if={@split && @status == :ready && !@busy}
            id="composer-plan-options"
            class="ab-questions ab-questions--options"
            phx-mounted={JS.ignore_attributes(["open"])}
          >
            <summary>{gettext("Change the plan")}</summary>
            <p class="ab-meta">
              {gettext(
                "A new AI proposal replaces the task edits. Returning to one issue keeps your request and answers in a draft."
              )}
            </p>
            <button
              id="composer-split"
              type="button"
              phx-click="composer_split"
              class="ab-btn ab-btn--sm"
            >{gettext("Regenerate with AI")}</button>
            <button
              id="composer-unsplit"
              type="button"
              phx-click="composer_unsplit"
              class="ab-btn ab-btn--sm ab-btn--quiet"
            >{gettext("Review as one issue")}</button>
          </details>
          <button
            :if={@split && @status != :ready && !@busy}
            id="composer-unsplit"
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet"
            phx-click="composer_unsplit"
          >
            {gettext("Review as one issue")}
          </button>
          <.private_context private={@private} />

          <p
            :if={@confirm && !@busy && !Intake.over_limit?(@selected_count, @max_tasks)}
            id="composer-confirm"
            class="ab-compose__confirm"
          >
            {@confirm}
            <span :if={@split && @selected_count > 1}>{gettext(
              "A separate GitHub issue will group these tasks."
            )}</span>
          </p>
        </div>

        <div class="ab-compose__bar">
          <label :if={@uploads} class="ab-btn ab-btn--sm ab-attach__pick">
            <.ico name="plus" />{gettext("Attach")}
            <.live_file_input upload={@uploads.attachments} class="ab-sr" />
          </label>

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
            :if={@status not in [:needs_clarification, :ready] && !@busy}
            id="composer-split"
            type="button"
            class="ab-btn ab-btn--sm"
            phx-click="composer_split"
            disabled={@ai_status == :not_configured or @busy or String.trim(@text) == ""}
            title={
              if @ai_status == :not_configured,
                do: gettext("AI is not configured"),
                else:
                  gettext(
                    "Ask AI for a new proposal. This replaces the proposed tasks without publishing them."
                  )
            }
          >
            <.ico name="split" />{if @split and not is_nil(@intake),
              do: gettext("Regenerate with AI"),
              else: gettext("Plan with AI")}
          </button>

          <span class="ab-top__spacer"></span>

          <button
            :if={!@split or @status in [:ready, :needs_clarification]}
            id={
              if @status == :needs_clarification,
                do: "composer-answer-submit",
                else: "composer-submit"
            }
            type="submit"
            class="ab-btn ab-btn--primary"
            phx-disable-with={disable_label(@split, @status)}
            disabled={
              submit_disabled?(@text, @split, @status, @selected_count, @busy) or
                (@status == :needs_clarification && !Clarifications.sufficient?(@spec, @answers)) or
                Intake.over_limit?(@selected_count, @max_tasks) or @incomplete or
                @attachments_pending
            }
          >
            {button_label(@split, @status, @selected_count)}<.kbd key="⌘↵" />
          </button>
        </div>
      </form>
    </div>
    """
  end

  attr :private, :map, required: true

  # What must not reach GitHub: kept on this machine, the issue gets the path.
  defp private_context(assigns) do
    assigns =
      assign(assigns,
        held: private_count(assigns.private),
        open: private_count(assigns.private) > 0 or assigns.private.folder_error != nil
      )

    ~H"""
    <details
      id="composer-private"
      class="ab-private"
      open={@open}
      phx-mounted={JS.ignore_attributes(["open"])}
    >
      <summary>
        <.ico name="lock" />{gettext("Private context")}
        <span class="ab-meta">
          {if @held > 0,
            do:
              ngettext("1 item, only on this machine", "%{count} items, only on this machine", @held),
            else: gettext("stays on this machine, never on GitHub")}
        </span>
      </summary>
      <p class="ab-meta">
        {gettext(
          "Passwords, keys, internal links, local mocks. The board writes them to a folder on this machine outside every repository; the issue only carries its path, and the AI split never reads them."
        )}
      </p>
      <label for="composer-private-note" class="ab-label">{gettext("Private notes")}</label>
      <textarea
        id="composer-private-note"
        name="private_note"
        rows="4"
        spellcheck="false"
        autocomplete="off"
        placeholder={gettext("e.g. staging password, API key, the account to test with")}
      >{@private.note}</textarea>

      <label for="composer-private-folder" class="ab-label">{gettext("Local folder")}</label>
      <div class="ab-private__folder">
        <input
          id="composer-private-folder"
          name="private_folder"
          type="text"
          value={@private.folder}
          placeholder="~/Downloads/claude-design-export"
          autocomplete="off"
          spellcheck="false"
          aria-describedby="composer-private-folder-hint"
          data-enter-click="composer-add-folder"
        />
        <button
          id="composer-add-folder"
          type="button"
          class="ab-btn ab-btn--sm"
          phx-click="composer_add_folder"
        >
          {gettext("Add folder")}
        </button>
      </div>
      <p :if={@private.folder_error} class="ab-compose__error" role="alert">
        {folder_error(@private.folder_error)}
      </p>
      <p id="composer-private-folder-hint" class="ab-meta">
        {gettext(
          "A folder under your home (a Claude Design export, before and after captures). It is copied at the send; hidden folders, .git and node_modules are left out."
        )}
      </p>
      <ul :if={@private.folders != [] or @private.files != []} class="ab-private__list">
        <li :for={folder <- @private.folders}>
          <span class="ab-attach__name">{folder.name}/</span>
          <span class="ab-meta">{folder_size(folder)}</span>
          <button
            type="button"
            class="ab-btn ab-btn--icon ab-btn--sm ab-btn--quiet"
            phx-click="composer_remove_folder"
            phx-value-path={folder.path}
            aria-label={gettext("Remove %{name}", name: folder.name)}
          >
            <.ico name="close" />
          </button>
        </li>
        <li :for={file <- @private.files}>
          <span class="ab-attach__name">{file.name}</span>
          <span class="ab-meta">{gettext("ready, only on this machine")}</span>
        </li>
      </ul>
    </details>
    """
  end

  defp private_count(private) do
    if(String.trim(private.note) == "", do: 0, else: 1) + length(private.folders) +
      length(private.files) + Enum.count(private.meta, fn {_ref, meta} -> meta.private end)
  end

  defp meta(private, ref), do: Map.get(private.meta, ref, %{private: false, role: "reference"})

  defp roles,
    do: [
      {"reference", gettext("Reference")},
      {"before", gettext("Before")},
      {"after", gettext("After")}
    ]

  defp folder_size(%{files: files, bytes: bytes}),
    do:
      ngettext("1 file", "%{count} files", files) <>
        " · " <> AgentBoardWeb.Numbers.bytes(bytes)

  defp folder_error(reason), do: PrivatePanel.folder_error(reason)

  attr :spec, :map, required: true

  # What the split rests on: the questions stay in sight, the rest is one
  # click away. All of it goes into each issue.
  defp understood(assigns) do
    assigns = assign(assigns, :open, assigns.spec["open_questions"] || [])

    ~H"""
    <div class="ab-split-note">
      <section
        :if={@open != []}
        id="composer-open-questions"
        class="ab-questions"
        aria-labelledby="composer-optional-title"
      >
        <h3 id="composer-optional-title">{gettext("Optional decisions")}</h3>
        <p id="composer-optional-help" class="ab-meta">
          {gettext(
            "Your answers go into each selected issue when published. Editing here does not call AI. Leave a question blank to keep it open."
          )}
        </p>
        <.question_fields
          questions={Enum.uniq(@open)}
          answers={@spec["answers"] || %{}}
          group="shared_context[answers]"
          prefix="answer"
          help="composer-optional-help"
        />
      </section>
      <details
        id="composer-understood"
        class="ab-split__detail"
        phx-mounted={JS.ignore_attributes(["open"])}
      >
        <summary>{gettext("What the AI understood")}</summary>
        <p :if={@spec["goal"] not in [nil, ""]}>{@spec["goal"]}</p>
        <p id="composer-shared-help" class="ab-meta">
          {gettext("One item per line. Your edits apply to the objective and every selected task.")}
        </p>
        <div :for={
          {key, label} <- [
            {"constraints", gettext("Constraints")},
            {"assumptions", gettext("Assumptions")}
          ]
        }>
          <label for={"composer-shared-#{key}"} class="ab-label">{label}</label>
          <textarea
            id={"composer-shared-#{key}"}
            name={"shared_context[#{key}]"}
            aria-describedby="composer-shared-help"
            rows="2"
          >{Enum.join(@spec[key] || [], "\n")}</textarea>
        </div>
        <.spec_list title={gettext("Out of scope")} items={@spec["non_goals"]} />
      </details>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, default: nil

  defp spec_list(assigns) do
    ~H"""
    <div :if={@items not in [nil, []]}>
      <p class="ab-label">{@title}</p>
      <ul>
        <li :for={item <- @items}>{item}</li>
      </ul>
    </div>
    """
  end

  defp attachment_entries(nil), do: []
  defp attachment_entries(uploads), do: uploads.attachments.entries

  defp attachments_pending?(nil), do: false
  defp attachments_pending?(uploads), do: Enum.any?(uploads.attachments.entries, &(not &1.done?))

  defp image?(entry), do: entry.client_type in ~w(image/png image/jpeg image/webp image/gif)

  defp entry_status(entry, uploads) do
    case upload_errors(uploads.attachments, entry) do
      [error | _] -> upload_error(error)
      [] -> if entry.done?, do: gettext("ready"), else: "#{entry.progress}%"
    end
  end

  defp upload_level_errors(nil), do: []

  defp upload_level_errors(uploads),
    do: Enum.map(upload_errors(uploads.attachments), &upload_error/1)

  defp upload_error(:too_large), do: gettext("Larger than 20 MB")
  defp upload_error(:too_many_files), do: gettext("At most 8 files")
  defp upload_error(:not_accepted), do: gettext("Type not accepted")
  defp upload_error(_other), do: gettext("Could not read this file")

  attr :questions, :list, required: true
  attr :answers, :map, required: true
  attr :group, :string, required: true
  attr :prefix, :string, required: true
  attr :help, :string, required: true

  defp question_fields(assigns) do
    ~H"""
    <div :for={{question, index} <- Enum.with_index(@questions, 1)} class="ab-question">
      <% key = Intake.question_key(question) %>
      <label for={"composer-#{@prefix}-#{key}"}><span aria-hidden="true">{index}</span>{question}</label>
      <textarea
        id={"composer-#{@prefix}-#{key}"}
        name={"#{@group}[#{key}]"}
        rows="2"
        aria-describedby={@help}
      >{@answers[key]}</textarea>
    </div>
    """
  end

  defp incomplete?(tasks, selected) do
    tasks
    |> Enum.with_index()
    |> Enum.any?(fn {task, index} -> index in selected and not Intake.complete?(task) end)
  end

  defp dependency_label([]), do: gettext("No dependency: can run alongside the others")

  defp dependency_label(positions) do
    gettext("Depends on %{tasks}", tasks: Enum.map_join(positions, ", ", &(&1 + 1)))
  end

  defp step(receipt, _status, _job) when not is_nil(receipt), do: 3

  defp step(_receipt, status, _job) when status in [:ready, :needs_clarification, :no_tasks],
    do: 2

  defp step(_receipt, _status, _job), do: 1

  attr :receipt, :map, required: true
  attr :maintenance_path, :string, default: nil
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
      <p :if={@maintenance_path} id="composer-paused-agent" class="ab-meta">
        {gettext("DeepSeek is paused for this project.")}
        <.link patch={@maintenance_path} class="ab-btn ab-btn--sm ab-btn--quiet">
          {gettext("Open agent maintenance")}
        </.link>
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

  defp outcome_label({:error, reason}),
    do: gettext("failed: %{reason}", reason: failure_reason(reason))

  defp outcome_class(:created), do: "ab-tag--agent"
  defp outcome_class(:existing), do: nil
  defp outcome_class({:error, _}), do: "ab-tag--halt"

  @doc "The human reason for a failed creation."
  def failure_reason(:conflict), do: gettext("The issue already existed with another number")

  def failure_reason(:private_failed),
    do: gettext("The private context could not be written on this machine; try again")

  def failure_reason(:attachments_failed),
    do: gettext("The files could not be saved on GitHub; try again")

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
    do: ngettext("1 task ready for review", "%{count} tasks ready for review", length(tasks))

  defp split_head(:needs_clarification, _tasks), do: gettext("Clarify the request")
  defp split_head(:no_tasks, _tasks), do: gettext("AI did not propose tasks")
  defp split_head(_status, _tasks), do: ""

  defp submit_disabled?(_text, _split, _status, _count, true), do: true
  defp submit_disabled?(text, false, _status, _count, _busy), do: String.trim(text) == ""
  defp submit_disabled?(text, true, nil, _count, _busy), do: String.trim(text) == ""
  defp submit_disabled?(_text, true, :ready, count, _busy), do: count == 0
  defp submit_disabled?(_text, true, _status, _count, _busy), do: false

  defp button_label(false, _status, _count), do: gettext("Create issue on GitHub")

  defp button_label(true, :ready, 0), do: gettext("Select tasks to publish")

  defp button_label(true, :ready, count),
    do: ngettext("Publish 1 task on GitHub", "Publish %{count} tasks on GitHub", count)

  defp button_label(true, :needs_clarification, _count), do: gettext("Send answers to AI")
  defp button_label(true, _status, _count), do: gettext("Split request")

  defp disable_label(false, _status), do: gettext("Sending…")
  defp disable_label(true, :ready), do: gettext("Sending…")
  defp disable_label(true, _status), do: gettext("Splitting…")
end
