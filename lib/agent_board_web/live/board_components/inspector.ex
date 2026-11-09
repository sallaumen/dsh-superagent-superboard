defmodule AgentBoardWeb.BoardComponents.Inspector do
  @moduledoc "The task inspector: conversation, activity, AI calls and PR, without leaving the board."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1, kbd: 1]
  import AgentBoardWeb.BoardComponents.Markup, only: [markup: 1]
  import AgentBoardWeb.BoardComponents.StatusMark, only: [status_mark: 1]
  import AgentBoardWeb.BoardComponents.WorkTag, only: [work_tag: 1]

  alias AgentBoardWeb.BoardComponents.AgentAction
  alias AgentBoardWeb.Time

  attr :task, :any, required: true
  attr :comments, :list, required: true
  attr :tab, :string, required: true
  attr :activity, :list, required: true
  attr :calls, :list, required: true
  attr :executions, :list, default: []
  attr :runner_executions, :list, default: []
  attr :dispatch_paused, :boolean, default: false
  attr :dispatch_active, :boolean, default: false
  attr :dispatch_ceiling, :float, default: 5.0
  attr :dispatch_fallback, :any, default: nil
  attr :usage, :map, default: nil
  attr :pr, :any, default: nil
  attr :ci, :map, default: nil
  attr :tz_offset, :integer, default: 0
  attr :live, :boolean, default: false
  attr :failure, :map, default: nil
  attr :ask_draft, :string, default: ""
  attr :ask_sending, :map, default: nil
  attr :ask_error, :string, default: nil
  attr :ai_status, :atom, default: :not_configured
  attr :unblock, :any, default: nil
  attr :unblock_suggestions, :list, default: []
  attr :unblock_ai, :atom, default: :idle
  attr :inspector_blockers, :list, default: []
  attr :blocker_open, :boolean, default: false
  attr :blocker_title, :string, default: ""
  attr :blocker_body, :string, default: ""
  attr :blocker_pending, :any, default: nil

  def inspector(assigns) do
    tabs = [
      {"conversa", "Conversa", length(assigns.comments)},
      {"atividade", "Atividade", length(assigns.activity)},
      {"chamadas", "Chamadas de IA", length(assigns.calls)},
      {"execucoes", gettext("Executions"),
       length(assigns.executions) + length(assigns.runner_executions)},
      {"pr", "PR", nil}
    ]

    assigns =
      assigns
      |> assign(:tabs, tabs)
      |> assign(:now, DateTime.utc_now())
      |> assign(:totals, call_totals(assigns.calls))

    ~H"""
    <aside
      id="conversation"
      class="ab-insp"
      phx-hook="TaskConversation"
      data-task-id={@task.id}
      aria-label={"Detalhes da tarefa ##{@task.number}"}
    >
      <div class="ab-insp__head">
        <div class="ab-insp__bar">
          <.status_mark
            kind={status_kind(@task.state)}
            word={status_word(@task.state)}
            live={@task.state == "running" and @live}
          />
          <span class="ab-data-sm ab-faint">#{@task.number}</span>
          <span class="ab-top__spacer"></span>
          <.kbd key="Esc" />
          <button
            type="button"
            class="ab-btn ab-btn--icon ab-btn--sm"
            phx-click="close"
            aria-label={gettext("Close panel (Esc)")}
          >
            <.ico name="close" />
          </button>
        </div>

        <h2 id="conversation-title">{@task.title}</h2>

        <div class="ab-insp__facts">
          <span class="ab-meta">
            {gettext("opened %{age}", age: Time.ago(Time.age_seconds(@task.inserted_at, @now)))}
          </span>
          <span class="ab-meta">{gettext("updated %{age}",
            age: Time.ago(Time.age_seconds(@task.updated_at, @now))
          )}</span>
          <span :if={@task.started_at} class="ab-meta">
            {gettext("started at %{time}", time: Time.local_time(@task.started_at, @tz_offset))}
          </span>
          <.work_tag work_type={@task.work_type} size={@task.size} />
          <span :if={@task.executor} class="ab-meta">
            para o {AgentBoard.Executors.name(@task.executor)}
          </span>
          <span :if={@pr} class="ab-meta">PR #{@pr.number}</span>
          <span :if={@calls != []} class="ab-meta">
            {length(@calls)} {if length(@calls) == 1, do: "chamada", else: "chamadas"}
          </span>
          <a
            :if={@task.url}
            href={@task.url}
            target="_blank"
            rel="noopener noreferrer"
            class="ab-meta"
          >
            {gettext("GitHub issue")}
          </a>
        </div>

        <.failure_block :if={@failure} failure={@failure} task={@task} offset={@tz_offset} />

        <div :if={dispatchable?(@task)} class="ab-insp__dispatch" id="task-dispatch">
          <div class="ab-insp__dispatch-head">
            <span class="ab-label">{gettext("Local dispatch")}</span>
            <span :if={@dispatch_active} class="ab-tag ab-tag--agent">{gettext("In Progress")}</span>
            <span :if={@dispatch_paused} class="ab-tag ab-tag--stale">{gettext("paused dispatch")}</span>
          </div>

          <.live_component
            :if={
              not @dispatch_active and not @dispatch_paused and
                fallback_kind(@dispatch_fallback) not in [:none, :budget]
            }
            module={AgentAction}
            id={"dispatch-#{@task.id}"}
            mode={:dispatch}
            tone={:primary}
            task={@task}
            executor={dispatch_executor(@task, @dispatch_fallback)}
            ceiling_usd={@dispatch_ceiling}
            fallback={fallback_kind(@dispatch_fallback) == :switch}
            retry={fallback_kind(@dispatch_fallback) == :retry}
            reason={fallback_reason(@dispatch_fallback)}
            label={dispatch_label(@task, @dispatch_fallback)}
            confirm_label="Despachar"
            busy_label="Iniciando o runner…"
          />

          <p :if={fallback_reason(@dispatch_fallback)} class="ab-meta">
            {fallback_reason(@dispatch_fallback)}
          </p>
          <p :if={@dispatch_fallback == :none} class="ab-meta ab-fail__system">
            {gettext(
              "The last execution failed due to content (test, block, or question): the board does not switch executors automatically. Check the result in Executions."
            )}
          </p>
          <p :if={fallback_kind(@dispatch_fallback) == :budget} class="ab-meta ab-fail__system">
            {gettext(
              "Adjust the per-task cap in Settings before trying again; the board won't start another run on its own."
            )}
          </p>

          <p class="ab-meta">
            {gettext(
              "Claude Code or Codex runs in a worktree outside the board, with a %{ceiling} per-task cap. The session and result appear in Executions; nothing starts before confirmation.",
              ceiling: money(@dispatch_ceiling)
            )}
          </p>

          <button
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet"
            phx-click="toggle_dispatch"
          >
            {if @dispatch_paused, do: gettext("Resume dispatch"), else: gettext("Pause dispatch")}
          </button>
        </div>

        <div class="ab-insp__actions">
          <button
            :if={not (@task.stopped or @task.archived)}
            type="button"
            class="ab-btn ab-btn--sm"
            phx-click="inspector_tab"
            phx-value-tab="conversa"
          >{gettext("Ask")}</button>

          <.live_component
            :if={@failure && @failure.retry && @failure.ticket_id}
            module={AgentAction}
            id={"retry-#{@task.id}"}
            mode={:retry}
            tone={if @failure.state == :scheduled, do: :quiet, else: :primary}
            ticket_id={@failure.ticket_id}
            task_id={@task.id}
            repository_id={@task.repository_id}
            number={@task.number}
            label={@failure.retry}
            confirm_label="Pedir nova tentativa"
            busy_label="Pedindo ao agente…"
          />

          <.live_component
            :if={@dispatch_active and active_execution(@runner_executions)}
            module={AgentAction}
            id={"stop-execution-#{@task.id}"}
            mode={:stop_execution}
            tone={:halt}
            task={@task}
            execution={active_execution(@runner_executions)}
            label={gettext("Stop execution")}
            confirm_label={gettext("Stop execution")}
            cancel_label="Continuar rodando"
            busy_label="Parando…"
          />
          <button
            :if={@task.stopped or @task.archived}
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet"
            phx-click="act"
            phx-value-id={@task.id}
            phx-value-action="resume"
          >{gettext("Resume")}</button>
          <.live_component
            :if={not (@task.stopped or @task.archived)}
            module={AgentAction}
            id={"stop-#{@task.id}"}
            mode={:stop}
            tone={:halt}
            task_id={@task.id}
            task={@task}
            label="Parar"
            confirm_label="Parar a tarefa"
            busy_label="Parando…"
          />
          <button
            :if={not (@task.stopped or @task.archived)}
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet"
            phx-click="act"
            phx-value-id={@task.id}
            phx-value-action="archive"
          >{gettext("Archive")}</button>
        </div>

        <div class="ab-tabs" role="tablist" aria-label={gettext("Task details")}>
          <button
            :for={{key, label, count} <- @tabs}
            type="button"
            class="ab-tab"
            id={"inspector-tab-#{key}"}
            role="tab"
            aria-selected={to_string(@tab == key)}
            aria-controls={"inspector-panel-#{key}"}
            phx-click="inspector_tab"
            phx-value-tab={key}
          >
            {label}<span :if={count} class="ab-num">{count}</span>
          </button>
        </div>
      </div>

      <div
        class="ab-insp__body"
        id={"inspector-panel-#{@tab}"}
        role="tabpanel"
        aria-labelledby={"inspector-tab-#{@tab}"}
        tabindex="0"
      >
        <%= case @tab do %>
          <% "atividade" -> %>
            <.activity_tab activity={@activity} offset={@tz_offset} />
          <% "chamadas" -> %>
            <.calls_tab calls={@calls} totals={@totals} usage={@usage} offset={@tz_offset} />
          <% "execucoes" -> %>
            <.executions_tab
              executions={@executions}
              runner_executions={@runner_executions}
              task={@task}
              pr={@pr}
              offset={@tz_offset}
            />
          <% "pr" -> %>
            <.pr_tab pr={@pr} ci={@ci} offset={@tz_offset} />
          <% _ -> %>
            <.conversation_tab
              task={@task}
              comments={@comments}
              ask_sending={@ask_sending}
              offset={@tz_offset}
            />
        <% end %>
      </div>

      <div :if={@tab == "conversa"} class="ab-insp__foot">
        <%!-- The typed text and submit authorize the inline GitHub comment. --%>
        <div
          :if={
            (@unblock || @inspector_blockers != []) &&
              !(@ask_sending && @ask_sending.task_id == @task.id)
          }
          id="unblock-panel"
          class="ab-unblock"
          aria-label={gettext("Unlock Task")}
        >
          <div class="ab-unblock__head">
            <strong>{gettext("Unlock")}</strong>
            <span class="ab-meta">{gettext("The agent stopped and asked for your decision.")}</span>
          </div>

          <div :if={@unblock && @unblock.question} class="ab-unblock__quote">
            <span class="ab-meta">{gettext("Question")}</span>
            <p>{@unblock.question}</p>
          </div>

          <div :if={@unblock && @unblock.blockage} class="ab-unblock__quote">
            <span class="ab-meta">{gettext("Block")}</span>
            <p>{@unblock.blockage}</p>
          </div>

          <div :if={@inspector_blockers != []} class="ab-unblock__links">
            <span class="ab-meta">{gettext("Unblocking task")}</span>
            <a
              :for={blocker <- @inspector_blockers}
              href={blocker.url || "#"}
              target="_blank"
              rel="noopener"
            >
              #{blocker.number} — {blocker.title} ({blocker.state})
            </a>
          </div>

          <div :if={@unblock} class="ab-unblock__actions">
            <button
              id="suggest-unblock"
              type="button"
              class="ab-btn ab-btn--sm ab-btn--quiet"
              phx-click="suggest_unblock"
              disabled={@unblock_ai == :busy or @ai_status == :not_configured}
            >
              {if @unblock_ai == :busy,
                do: gettext("Generating suggestions…"),
                else: gettext("Suggest a response")}
            </button>
            <button
              id="open-blocker"
              type="button"
              class="ab-btn ab-btn--sm ab-btn--quiet"
              phx-click="open_blocker"
            >
              {gettext("Create blocking task")}
            </button>
          </div>

          <p :if={@ai_status == :not_configured} class="ab-meta">
            {gettext("AI not configured; write the response below or create the blocking task.")}
          </p>

          <p :if={@unblock_ai == :error} class="ab-unblock__error" role="status">
            {gettext(
              "Could not generate suggestions. Write the response or create the blocking task."
            )}
          </p>

          <div :if={@unblock_suggestions != []} class="ab-unblock__suggestions" aria-live="polite">
            <span class="ab-meta">{gettext("Suggestions — click to edit before sending")}</span>
            <button
              :for={suggestion <- @unblock_suggestions}
              type="button"
              class="ab-unblock__suggestion"
              phx-click="use_unblock_suggestion"
              phx-value-text={suggestion}
            >
              {suggestion}
            </button>
          </div>

          <div :if={@blocker_open} class="ab-unblock__form">
            <form id="blocker-form" phx-submit="blocker_prepare">
              <label for="blocker-title">{gettext("Task title")}</label>
              <input
                id="blocker-title"
                name="title"
                type="text"
                value={@blocker_title}
                required
              />
              <label for="blocker-body">{gettext("What needs to be resolved")}</label>
              <textarea id="blocker-body" name="body" rows="8" required>{@blocker_body}</textarea>
              <div class="ab-unblock__form-actions">
                <button type="submit" class="ab-btn ab-btn--sm ab-btn--primary">
                  {gettext("Prepare task")}
                </button>
                <button
                  type="button"
                  class="ab-btn ab-btn--sm ab-btn--quiet"
                  phx-click="close_blocker"
                >
                  {gettext("Cancel")}
                </button>
              </div>
            </form>
          </div>

          <div
            :if={@blocker_pending}
            id="blocker-confirm"
            class="ab-act__confirm"
            role="group"
            aria-labelledby="blocker-confirm-q"
          >
            <p id="blocker-confirm-q" class="ab-act__question">{@blocker_pending.phrase}</p>
            <div class="ab-act__buttons">
              <button
                type="button"
                class="ab-btn ab-btn--sm ab-btn--primary"
                phx-click="blocker_confirm"
                phx-disable-with={gettext("Creating…")}
              >
                {gettext("Create task")}
              </button>
              <button
                type="button"
                class="ab-btn ab-btn--sm ab-btn--quiet"
                phx-click="blocker_cancel"
              >
                {gettext("Back and edit")}
              </button>
            </div>
          </div>
        </div>

        <form id="ask-agent" phx-change="ask_change" phx-submit="ask">
          <div class="ab-compose ab-compose--inline">
            <textarea
              id="ask-body"
              name="body"
              rows="2"
              phx-debounce="300"
              aria-label={gettext("Message to the agent")}
              placeholder={gettext("Respond to agent...")}
              disabled={@ask_sending && @ask_sending.task_id == @task.id}
              required
            >{@ask_draft}</textarea>
            <div class="ab-compose__bar">
              <button
                type="button"
                class="ab-btn ab-btn--icon ab-btn--sm"
                phx-click="show_panel"
                phx-value-panel="voice"
                aria-label={gettext("Dictate by voice")}
              >
                <.ico name="mic" />
              </button>
              <span class="ab-top__spacer"></span>
              <button
                class="ab-btn ab-btn--primary ab-btn--sm"
                disabled={@ask_sending && @ask_sending.task_id == @task.id}
                phx-disable-with={gettext("Sending…")}
              >
                {if @ask_sending && @ask_sending.task_id == @task.id,
                  do: gettext("Sending…"),
                  else: gettext("Send")}
                <.kbd :if={is_nil(@ask_sending)} key="↵" />
              </button>
            </div>
            <p class="ab-compose__hint">
              {gettext(
                "This message is posted on GitHub issue #%{number} and mentions the agent when you send it.",
                number: @task.number
              )}
            </p>
            <p :if={@ask_error} class="ab-compose__error" role="alert">{@ask_error}</p>
          </div>
        </form>
      </div>
    </aside>
    """
  end

  attr :failure, :map, required: true
  attr :task, :any, required: true
  attr :offset, :integer, default: 0

  # What failed, what the board does about it, what is left to the owner,
  # then the evidence: the whole error and every attempt.
  defp failure_block(assigns) do
    ~H"""
    <section
      id="agent-failure"
      class={["ab-fail", "is-#{@failure.state}"]}
      aria-labelledby="agent-failure-title"
    >
      <h3 id="agent-failure-title" class="ab-fail__title">{@failure.headline}</h3>
      <p class="ab-fail__system">{@failure.system}</p>
      <p class="ab-fail__action">{@failure.action}</p>

      <details class="ab-fail__evidence">
        <summary>{gettext("Errors and attempts")}</summary>
        <pre :if={@failure.error} class="ab-fail__error">{@failure.error}</pre>
        <ol class="ab-fail__attempts">
          <li :for={attempt <- @failure.attempts}>
            <span class="ab-data-sm ab-faint">{attempt.n}</span>
            <span :if={attempt.at} class="ab-meta">{Time.local_time(attempt.at, @offset)}</span>
            <span>{attempt.text}</span>
          </li>
        </ol>
      </details>
    </section>
    """
  end

  # The executor writes hidden routing markers into issue comments; they are
  # not part of the message a person reads.
  defp clean_body(nil), do: ""

  defp clean_body(body) do
    body
    |> String.replace(~r/<!--.*?-->/s, "")
    |> String.replace(~r/\s*@sallaumen-agent\s*$/i, "")
    |> String.trim()
  end

  defp conversation_tab(assigns) do
    ~H"""
    <div class="ab-conversation">
      <div
        :if={@task.body not in [nil, ""]}
        class="ab-msg ab-msg--you"
        data-message-id={"task-#{@task.id}"}
      >
        <div class="ab-msg__who">
          {gettext("Task")}
          <span class="ab-data-sm">{Time.local_time(@task.inserted_at, @offset)}</span>
        </div>
        <p>{clean_body(@task.body)}</p>
      </div>

      <div
        :for={comment <- @comments}
        class={[
          "ab-msg",
          comment.kind == "agent" && "ab-msg--agent",
          comment.kind != "agent" && "ab-msg--you",
          sending_comment?(comment, @ask_sending, @task.id) && "ab-msg--sending"
        ]}
        data-message-id={"comment-#{comment.id}"}
        data-message-sending={sending_comment?(comment, @ask_sending, @task.id)}
      >
        <div class="ab-msg__who">
          {if comment.kind == "agent", do: comment.author || gettext("Agent"), else: gettext("You")}
          <span class="ab-data-sm">{Time.local_time(comment.inserted_at, @offset)}</span>
        </div>
        <p><.markup text={clean_body(comment.body)} /></p>
        <span
          :if={sending_comment?(comment, @ask_sending, @task.id)}
          class="ab-msg__delivery"
          role="status"
        >{gettext("Sending…")}</span>
      </div>

      <div
        :if={sending_placeholder?(@ask_sending, @comments, @task.id)}
        class="ab-msg ab-msg--you ab-msg--sending"
        data-message-id="sending"
        data-message-sending="true"
      >
        <div class="ab-msg__who">{gettext("You")}</div>
        <p>{@ask_sending.body}</p>
        <span class="ab-msg__delivery" role="status">{gettext("Sending…")}</span>
      </div>

      <div
        :if={
          @comments == [] and @task.body in [nil, ""] and
            !sending_placeholder?(@ask_sending, @comments, @task.id)
        }
        class="ab-sec__empty"
      >
        {gettext("No conversation in this task.")}
      </div>

      <div :if={@comments == [] and @task.body not in [nil, ""]} class="ab-sec__empty">
        {gettext("No response yet. The agent receives the message via GitHub.")}
      </div>
    </div>
    """
  end

  defp sending_comment?(comment, %{task_id: task_id, body: body}, task_id),
    do: comment.github_id < 0 and clean_body(comment.body) == body

  defp sending_comment?(_comment, _sending, _task_id), do: false

  defp sending_placeholder?(%{task_id: task_id} = sending, comments, task_id),
    do: not Enum.any?(comments, &sending_comment?(&1, sending, task_id))

  defp sending_placeholder?(_sending, _comments, _task_id), do: false

  defp activity_tab(assigns) do
    ~H"""
    <div>
      <div :if={@activity == []} class="ab-sec__empty">{gettext("No activity recorded.")}</div>
      <ol :if={@activity != []} class="ab-tl">
        <li :for={item <- @activity}>
          <span class="ab-data-sm">{Time.local_time(item.at, @offset)}</span>
          <span class={[
            "ab-tl__dot",
            item.tone == :agent && "is-agent",
            item.tone == :halt && "is-halt"
          ]}></span>
          <span class="ab-tl__txt">
            <a :if={item[:url]} href={item.url} target="_blank" rel="noopener noreferrer">{item.text}</a>
            <.markup :if={!item[:url]} text={item.text} />
          </span>
        </li>
      </ol>
    </div>
    """
  end

  defp calls_tab(assigns) do
    ~H"""
    <div>
      <div :if={@calls == []} class="ab-sec__empty">
        {gettext("No AI calls recorded for this task.")}
      </div>

      <div
        :if={@calls != []}
        class="ab-table-wrap"
        tabindex="0"
        role="region"
        aria-label={gettext("AI Calls")}
      >
        <table class="ab-table">
          <thead>
            <tr>
              <th>{gettext("Time")}</th>
              <th>{gettext("Model")}</th>
              <th class="r">{gettext("Input")}</th>
              <th class="r">{gettext("Output")}</th>
              <th class="r">{gettext("Duration")}</th>
              <th class="r">{gettext("Cost")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={call <- Enum.reverse(@calls)}>
              <td>{Time.local_time(call.inserted_at, @offset)}</td>
              <td>{call.model || gettext("unknown")}</td>
              <td class="r">{tokens(call.input_tokens)}</td>
              <td class="r">{tokens(call.output_tokens)}</td>
              <td class="r">{duration(call.duration_ms)}</td>
              <td class="r">{cost(call.cost_micros)}</td>
            </tr>
          </tbody>
          <tfoot>
            <tr>
              <td colspan="2">
                {length(@calls)} {if length(@calls) == 1, do: "chamada", else: "chamadas"}
              </td>
              <td class="r">{tokens(@totals.input)}</td>
              <td class="r">{tokens(@totals.output)}</td>
              <td class="r">{duration(@totals.duration)}</td>
              <td class="r">{total_cost(@totals)}</td>
            </tr>
          </tfoot>
        </table>
      </div>

      <p :if={@calls != []} class="ab-meta">
        {gettext("Calls made by the board.")}
        <span :if={@totals.missing_cost}>{gettext(
          "Missing cost appears as —; the total is a minimum."
        )}</span>
      </p>

      <.executor_usage usage={@usage} />
    </div>
    """
  end

  attr :executions, :list, required: true
  attr :runner_executions, :list, default: []
  attr :task, :any, required: true
  attr :pr, :any, default: nil
  attr :offset, :integer, default: 0

  defp executions_tab(assigns) do
    ~H"""
    <div>
      <p class="ab-meta">
        {gettext("Task Result:")} <b>{task_result(@task, @pr)}</b>.
        <span :if={@executions == [] and @runner_executions == []}>
          {gettext("No runs for this task in the usage ledger.")}
        </span>
      </p>

      <section
        :if={@runner_executions != []}
        class="ab-runner-list"
        aria-labelledby="runner-list-title"
      >
        <h3 id="runner-list-title" class="ab-label">{gettext("Board dispatches")}</h3>
        <article
          :for={execution <- @runner_executions}
          class="ab-runner-row"
          id={"runner-#{execution.id}"}
        >
          <header class="ab-runner-row__head">
            <b>{executor_label(execution.executor)}</b>
            <span class={["ab-tag", runner_tag(execution.status)]}>
              {runner_status(execution.status)}
            </span>
            <span
              :if={execution.cost_micros}
              class="ab-meta"
              title={gettext("List price provided by CLI; not the invoice")}
            >
              ≈ {money(execution.cost_micros / 1_000_000)} lista
            </span>
            <span class="ab-meta">
              {runner_time(execution.started_at, @offset)}–{runner_time(
                execution.finished_at,
                @offset
              )}
            </span>
          </header>
          <p class="ab-meta">
            <span :if={execution.session_id}>{gettext("session %{id} · ", id: execution.session_id)}</span>
            branch {execution.branch || "—"}
          </p>
          <p :if={execution.error} class="ab-runner-row__error">{execution.error}</p>
          <p :if={execution.result} class="ab-runner-row__result">{execution.result}</p>
        </article>
      </section>

      <ol :if={@executions != []} class="ab-exec-list">
        <li :for={execution <- @executions} class="ab-exec-row">
          <div class="ab-exec-row__head">
            <span class="ab-exec-row__name">{executor_label(execution.source)}</span>
            <span class="ab-meta">{models(execution.models)}</span>
            <span class="ab-data-sm ab-faint">
              {Time.local_time(execution.first_at, @offset)}–{Time.local_time(
                execution.last_at,
                @offset
              )}
            </span>
          </div>
          <dl class="ab-exec-row__facts">
            <div>
              <dt>{gettext("Requests")}</dt><dd>{execution.requests}</dd>
            </div>
            <div>
              <dt>{gettext("Input")}</dt><dd>{tokens(execution.input_tokens)}</dd>
            </div>
            <div>
              <dt>{gettext("Output")}</dt><dd>{tokens(execution.output_tokens)}</dd>
            </div>
            <div>
              <dt>{gettext("Cost")}</dt><dd>{execution_cost(execution)}</dd>
            </div>
          </dl>
        </li>
      </ol>

      <p :if={@executions != []} class="ab-meta">
        {gettext(
          "Tokens measured. Cost is estimated in each executor's currency; \"list\" is the reference price for Claude Max, not the invoice. Codex has no USD: weekly allowance appears on the Executors panel. A session without a PR branch or direct link does not appear as a task, and the ledger does not store each session's result."
        )}
      </p>
    </div>
    """
  end

  defp active_execution(executions) do
    Enum.find(executions, &(&1.status in ["starting", "running"]))
  end

  defp fallback_kind(%{kind: kind}), do: kind
  defp fallback_kind(_fallback), do: nil

  defp fallback_reason(%{reason: reason}), do: reason
  defp fallback_reason(_fallback), do: nil

  defp dispatch_executor(_task, %{executor: executor}), do: executor
  defp dispatch_executor(task, _fallback), do: task.executor

  defp dispatch_label(_task, %{kind: :switch, executor: executor}),
    do: "Mandar para o #{AgentBoard.Executors.name(executor)}"

  defp dispatch_label(_task, %{kind: :retry, executor: executor}),
    do: "Tentar de novo no #{AgentBoard.Executors.name(executor)}"

  defp dispatch_label(task, _fallback),
    do: gettext("Dispatch to %{executor}", executor: AgentBoard.Executors.name(task.executor))

  # A dispatch belongs to a task that can still run: queued, blocked after a
  # failure, or already running. A task waiting for review or finished has
  # its result in Executions, not another dispatch button.
  defp dispatchable?(task) do
    task.executor in ["claude", "codex"] and task.state in ["queued", "blocked", "running"] and
      not (task.stopped or task.archived)
  end

  defp runner_status("starting"), do: gettext("starting")
  defp runner_status("running"), do: gettext("running")
  defp runner_status("done"), do: gettext("Completed")
  defp runner_status("failed"), do: gettext("failed")
  defp runner_status("stopped"), do: gettext("stopped")
  defp runner_status(status), do: status

  defp runner_tag("done"), do: "ab-tag--agent"
  defp runner_tag("failed"), do: "ab-tag--halt"
  defp runner_tag("running"), do: "ab-tag--you"
  defp runner_tag("stopped"), do: "ab-tag--stale"
  defp runner_tag(_status), do: ""

  defp runner_time(nil, _offset), do: "—"

  defp runner_time(%NaiveDateTime{} = at, offset),
    do: Time.local_time(DateTime.from_naive!(at, "Etc/UTC"), offset)

  defp runner_time(%DateTime{} = at, offset), do: Time.local_time(at, offset)

  defp money(nil), do: "—"

  defp money(usd) when is_number(usd) do
    amount = :erlang.float_to_binary(usd / 1, decimals: 2) |> String.replace(".", ",")
    "US$ " <> amount
  end

  defp executor_label("dsh"), do: "DeepSeek"
  defp executor_label("claude_code"), do: "Claude Code"
  defp executor_label("codex"), do: "Codex"
  defp executor_label(source), do: source

  defp execution_cost(%{source: "codex"}), do: gettext("unknown")
  defp execution_cost(%{cost: nil}), do: gettext("unknown")

  defp execution_cost(%{source: "claude_code", cost: %{micros: micros, complete?: true}}),
    do: "≈ #{cost(micros)} " <> gettext("list price")

  defp execution_cost(%{source: "claude_code", cost: %{micros: micros}}),
    do: "≥ #{cost(micros)} " <> gettext("list price")

  defp execution_cost(%{cost: %{micros: micros, complete?: true}}), do: "≈ #{cost(micros)}"
  defp execution_cost(%{cost: %{micros: micros}}), do: "≥ #{cost(micros)}"

  defp task_result(task, pr) do
    word = task_result_label(task.state)
    if pr, do: "#{word}, PR ##{pr.number}", else: word
  end

  defp task_result_label("done"), do: gettext("merged")
  defp task_result_label("blocked"), do: gettext("blocked")
  defp task_result_label("question"), do: gettext("question")
  defp task_result_label("ready"), do: gettext("ready for review")
  defp task_result_label("running"), do: gettext("in progress")
  defp task_result_label("retrying"), do: gettext("retrying")
  defp task_result_label("queued"), do: gettext("queued")
  defp task_result_label("stopped"), do: gettext("stopped")
  defp task_result_label("archived"), do: gettext("archived")
  defp task_result_label("closed"), do: gettext("closed without merge")
  defp task_result_label(_), do: gettext("unknown")

  attr :usage, :map, default: nil

  defp executor_usage(%{usage: nil} = assigns), do: ~H""

  defp executor_usage(%{usage: %{status: :none}} = assigns) do
    ~H"""
    <section id="executor-usage" class="ab-insp__usage">
      <h3 class="ab-label">{gettext("Agent Executor")}</h3>
      <p class="ab-meta">{gettext("No executor transcript for this task.")}</p>
    </section>
    """
  end

  defp executor_usage(%{usage: %{status: :unavailable}} = assigns) do
    ~H"""
    <section id="executor-usage" class="ab-insp__usage">
      <h3 class="ab-label">{gettext("Agent Executor")}</h3>
      <p class="ab-meta">
        {gettext("Transcripts exist, but the board can't read them: missing the")} <code>{gettext("zstd")}</code>.
      </p>
    </section>
    """
  end

  defp executor_usage(assigns) do
    ~H"""
    <section id="executor-usage" class="ab-insp__usage">
      <h3 class="ab-label">{gettext("Agent Executor")}</h3>
      <table class="ab-table">
        <thead>
          <tr>
            <th>{gettext("Sessions")}</th>
            <th class="r">{gettext("Requests")}</th>
            <th class="r">{gettext("Input")}</th>
            <th class="r">{gettext("Output")}</th>
            <th class="r">{gettext("Cache reads")}</th>
            <th class="r">{gettext("Estimated Cost")}</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>{sessions(@usage)}</td>
            <td class="r">{@usage.requests}</td>
            <td class="r">{tokens(@usage.input)}</td>
            <td class="r">{tokens(@usage.output)}</td>
            <td class="r">{tokens(@usage.cache_read)}</td>
            <td class="r">{usage_cost(@usage.cost)}</td>
          </tr>
        </tbody>
      </table>
      <p class="ab-meta">
        {gettext(
          "Measured from local executor transcripts (%{models}). Cost uses the board's pricing table.",
          models: models(@usage.models)
        )}
        <span :if={@usage.cost && not @usage.cost.complete?}>
          {gettext("Some token type has no price in the table (cache read today); cost is a minimum.")}
        </span>
        <span :if={@usage.cost == nil}>{gettext("The model has no price in the table; cost unknown.")}</span>
        <span :if={@usage.unreadable > 0}>
          {ngettext(
            "%{count} unreadable transcript; these numbers are a minimum.",
            "%{count} unreadable transcripts; these numbers are a minimum.",
            @usage.unreadable
          )}
        </span>
      </p>
    </section>
    """
  end

  defp sessions(%{workers: workers, subagents: 0}), do: "#{workers} worker"

  defp sessions(%{workers: workers, subagents: subagents}),
    do:
      gettext("%{workers} worker + %{subagents} subagents",
        workers: workers,
        subagents: subagents
      )

  defp models([]), do: gettext("unknown model")
  defp models(models), do: Enum.join(models, ", ")

  defp usage_cost(nil), do: "—"
  defp usage_cost(%{micros: micros, complete?: true}), do: cost(micros)
  defp usage_cost(%{micros: micros, complete?: false}) when micros > 0, do: "≥ #{cost(micros)}"
  defp usage_cost(_), do: "—"

  defp pr_tab(assigns) do
    ~H"""
    <div>
      <div :if={is_nil(@pr)} class="ab-sec__empty">
        {gettext("This task has not opened a PR yet.")}
      </div>

      <div :if={@pr} class="ab-pr-facts">
        <div class="ab-need__title">
          <span class="ab-need__id">#{@pr.number}</span>
          <span>{@pr.title}</span>
        </div>
        <div class="ab-insp__facts">
          <.status_mark kind={pr_kind(@pr, @ci)} word={pr_word(@pr, @ci)} />
          <span :if={@pr.merged_at} class="ab-meta">
            mesclado às {Time.local_time(@pr.merged_at, @offset)}
          </span>
          <span
            class={["ab-meta", local_ci_pass?(@ci) && "ab-ci-local"]}
            title={pr_ci_title(@pr, @ci)}
          >
            {pr_ci(@pr, @ci)}
          </span>
          <span class="ab-meta">{pr_review(@pr.review_state)}</span>
        </div>
        <a
          :if={@pr.url}
          class="ab-btn ab-btn--sm"
          href={@pr.url}
          target="_blank"
          rel="noopener noreferrer"
        ><.ico name="ext" />{gettext("Open on GitHub")}</a>
      </div>
    </div>
    """
  end

  defp status_kind("running"), do: :run
  defp status_kind("question"), do: :question
  defp status_kind("ready"), do: :review
  defp status_kind("blocked"), do: :blocked
  defp status_kind("retrying"), do: :retrying
  defp status_kind("queued"), do: :queue
  defp status_kind("done"), do: :done
  defp status_kind("stopped"), do: :queue
  defp status_kind("archived"), do: :queue
  defp status_kind(_state), do: :unknown

  defp status_word("stopped"), do: "Parado"
  defp status_word("archived"), do: "Arquivado"
  defp status_word(_state), do: nil

  defp pr_kind(_pr, %{state: :fail}), do: :cifail
  defp pr_kind(%{state: "merged"}, _ci), do: :done
  defp pr_kind(_pr, _ci), do: :review

  defp pr_word(_pr, %{state: :fail}), do: gettext("Local CI failed")
  defp pr_word(%{state: "merged"}, _ci), do: gettext("Merged")
  defp pr_word(_pr, _ci), do: gettext("Open")

  defp pr_ci(_pr, %{state: :pass}), do: gettext("Local CI passed")
  defp pr_ci(_pr, %{state: :fail}), do: gettext("Local CI failed")
  defp pr_ci(_pr, %{state: :stale}), do: gettext("Local CI unknown")
  defp pr_ci(%{checks_state: "failure"}, _ci), do: gettext("Local CI unknown")
  defp pr_ci(%{checks_state: "success"}, _ci), do: gettext("CI passed")
  defp pr_ci(%{checks_state: "none"}, _ci), do: gettext("no CI")
  defp pr_ci(_pr, _ci), do: gettext("CI unknown")

  defp pr_ci_title(_pr, %{state: :pass, detail: detail, remote_blocked: true} = ci) do
    gettext("GitHub Actions did not run (billing/no credit). ") <> local_scope(ci) <> detail
  end

  defp pr_ci_title(_pr, %{state: :pass, detail: detail} = ci),
    do: local_scope(ci) <> detail

  defp pr_ci_title(_pr, %{state: :fail, detail: detail}),
    do: gettext("Local CI failed: %{detail}", detail: detail)

  defp pr_ci_title(_pr, %{state: :stale, detail: detail}), do: detail

  defp pr_ci_title(%{checks_state: "failure"}, _ci),
    do: gettext("GitHub Actions failed (billing/no credit); no evidence of local CI.")

  defp pr_ci_title(%{checks_state: "success"}, _ci), do: gettext("GitHub Actions passed.")
  defp pr_ci_title(_pr, _ci), do: gettext("No remote checks configured.")

  defp local_scope(%{scope: :ticket, evidence_pr: number}),
    do:
      gettext(
        "Local CI passed on the ticket (report cites #%{number}); this PR is from the same work: ",
        number: number
      )

  defp local_scope(_ci), do: gettext("Local CI passed: ")

  defp local_ci_pass?(%{state: :pass}), do: true
  defp local_ci_pass?(_ci), do: false

  defp pr_review("approved"), do: gettext("reviewed")
  defp pr_review("changes_requested"), do: gettext("changes requested")
  defp pr_review("pending"), do: gettext("pending review")
  defp pr_review(_state), do: gettext("no review")

  defp call_totals(calls) do
    %{
      input: sum(calls, & &1.input_tokens),
      output: sum(calls, & &1.output_tokens),
      duration: sum(calls, & &1.duration_ms),
      known_cost:
        calls
        |> Enum.map(& &1.cost_micros)
        |> Enum.filter(&(is_integer(&1) and &1 > 0))
        |> Enum.sum(),
      missing_cost: Enum.any?(calls, &(not is_integer(&1.cost_micros) or &1.cost_micros <= 0))
    }
  end

  defp sum(calls, fun) do
    calls
    |> Enum.map(fun)
    |> Enum.filter(&is_integer/1)
    |> case do
      [] -> nil
      values -> Enum.sum(values)
    end
  end

  defp tokens(nil), do: "—"
  defp tokens(0), do: "—"
  defp tokens(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp tokens(n) when n >= 1000, do: "#{Float.round(n / 1000, 1)}k"
  defp tokens(n), do: to_string(n)

  defp duration(nil), do: "—"
  defp duration(0), do: "—"
  defp duration(ms) when ms >= 1000, do: "#{Float.round(ms / 1000, 1)} s"
  defp duration(ms), do: "#{ms} ms"

  defp cost(nil), do: "—"
  defp cost(micros) when micros <= 0, do: "—"

  defp cost(micros) do
    dollars = div(micros, 1_000_000)
    cents = micros |> rem(1_000_000) |> div(10_000)
    "$#{dollars}.#{String.pad_leading(to_string(cents), 2, "0")}"
  end

  defp total_cost(%{known_cost: 0, missing_cost: true}), do: "—"
  defp total_cost(%{known_cost: known, missing_cost: true}), do: "≥ #{cost(known)}"
  defp total_cost(%{known_cost: known}), do: cost(known)
end
