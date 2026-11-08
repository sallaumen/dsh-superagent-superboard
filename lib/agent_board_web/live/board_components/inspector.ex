defmodule AgentBoardWeb.BoardComponents.Inspector do
  @moduledoc "The task inspector: conversation, activity, AI calls and PR, without leaving the board."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1, kbd: 1]
  import AgentBoardWeb.BoardComponents.Markup, only: [markup: 1]
  import AgentBoardWeb.BoardComponents.StatusMark, only: [status_mark: 1]
  import AgentBoardWeb.BoardComponents.WorkTag, only: [work_tag: 1]

  alias AgentBoard.Time
  alias AgentBoardWeb.BoardComponents.AgentAction

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
  attr :ask_pending, :map, default: nil
  attr :ask_draft, :string, default: ""

  def inspector(assigns) do
    tabs = [
      {"conversa", "Conversa", length(assigns.comments)},
      {"atividade", "Atividade", length(assigns.activity)},
      {"chamadas", "Chamadas de IA", length(assigns.calls)},
      {"execucoes", "Execuções", length(assigns.executions) + length(assigns.runner_executions)},
      {"pr", "PR", nil}
    ]

    assigns =
      assigns
      |> assign(:tabs, tabs)
      |> assign(:now, DateTime.utc_now())
      |> assign(:totals, call_totals(assigns.calls))

    ~H"""
    <aside id="conversation" class="ab-insp" aria-label={"Detalhes da tarefa ##{@task.number}"}>
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
            aria-label="Fechar painel (Esc)"
          >
            <.ico name="close" />
          </button>
        </div>

        <h2 id="conversation-title">{@task.title}</h2>

        <div class="ab-insp__facts">
          <span class="ab-meta">atualizado {Time.ago(Time.age_seconds(@task.updated_at, @now))}</span>
          <span :if={@task.started_at} class="ab-meta">
            começou às {Time.local_time(@task.started_at, @tz_offset)}
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
            Issue no GitHub
          </a>
        </div>

        <.failure_block :if={@failure} failure={@failure} task={@task} offset={@tz_offset} />

        <div :if={dispatchable?(@task)} class="ab-insp__dispatch" id="task-dispatch">
          <div class="ab-insp__dispatch-head">
            <span class="ab-label">Despacho local</span>
            <span :if={@dispatch_active} class="ab-tag ab-tag--agent">execução em andamento</span>
            <span :if={@dispatch_paused} class="ab-tag ab-tag--stale">despacho pausado</span>
          </div>

          <.live_component
            :if={@dispatch_active and active_execution(@runner_executions)}
            module={AgentAction}
            id={"stop-execution-#{@task.id}"}
            mode={:stop_execution}
            tone={:halt}
            task={@task}
            execution={active_execution(@runner_executions)}
            label="Parar execução"
            confirm_label="Parar execução"
            busy_label="Parando…"
          />

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
            A última execução falhou por conteúdo (teste, bloqueio ou pergunta):
            o board não troca de executor sozinho. Confira o resultado em Execuções.
          </p>
          <p :if={fallback_kind(@dispatch_fallback) == :budget} class="ab-meta ab-fail__system">
            Ajuste o teto por tarefa em Configurações antes de tentar de novo;
            o board não inicia outra execução sozinho.
          </p>

          <p class="ab-meta">
            O Claude Code ou o Codex roda num worktree fora do board, com teto de {money(
              @dispatch_ceiling
            )} por tarefa. A sessão e o resultado aparecem
            em Execuções; nada começa sem a confirmação.
          </p>

          <button
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet"
            phx-click="toggle_dispatch"
          >
            {if @dispatch_paused, do: "Retomar despacho", else: "Pausar despacho"}
          </button>
        </div>

        <div class="ab-insp__actions">
          <button
            :if={@task.stopped or @task.archived}
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet"
            phx-click="act"
            phx-value-id={@task.id}
            phx-value-action="resume"
          >Retomar</button>
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
          >Arquivar</button>
        </div>

        <div class="ab-tabs" role="tablist" aria-label="Detalhes da tarefa">
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
            <.conversation_tab task={@task} comments={@comments} offset={@tz_offset} />
        <% end %>
      </div>

      <div :if={@tab == "conversa"} class="ab-insp__foot">
        <%!-- A question posts on GitHub (red, AgentBoard.Actions): the
             sentence comes first, and only "Mandar" sends it. --%>
        <div
          :if={@ask_pending && @ask_pending.task_id == @task.id}
          id="ask-confirm"
          class="ab-act__confirm"
          role="group"
          aria-labelledby="ask-confirm-q"
        >
          <p id="ask-confirm-q" class="ab-act__question">{@ask_pending.phrase}</p>
          <div class="ab-act__buttons">
            <button
              id="ask-confirm-go"
              type="button"
              class="ab-btn ab-btn--sm ab-btn--primary"
              phx-click="ask_confirm"
              phx-disable-with="Mandando…"
              phx-mounted={Phoenix.LiveView.JS.focus()}
            >
              Mandar a pergunta
            </button>
            <button
              id="ask-confirm-cancel"
              type="button"
              class="ab-btn ab-btn--sm ab-btn--quiet"
              phx-click="ask_cancel"
            >
              Voltar e editar
            </button>
          </div>
        </div>
        <form
          :if={!(@ask_pending && @ask_pending.task_id == @task.id)}
          id="ask-agent"
          phx-submit="ask"
        >
          <div class="ab-compose ab-compose--inline">
            <textarea
              id="ask-body"
              name="body"
              rows="2"
              aria-label="Mensagem para o agente"
              placeholder="Responder ao agente…"
              required
            >{@ask_draft}</textarea>
            <div class="ab-compose__bar">
              <button
                type="button"
                class="ab-btn ab-btn--icon ab-btn--sm"
                phx-click="show_panel"
                phx-value-panel="voice"
                aria-label="Ditar por voz"
              >
                <.ico name="mic" />
              </button>
              <span class="ab-top__spacer"></span>
              <button class="ab-btn ab-btn--primary ab-btn--sm" phx-disable-with="Enviando…">
                Enviar <.kbd key="⌘↵" />
              </button>
            </div>
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

      <.live_component
        :if={@failure.retry && @failure.ticket_id}
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

      <details class="ab-fail__evidence">
        <summary>Erro e tentativas</summary>
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
      <div :if={@task.body not in [nil, ""]} class="ab-msg ab-msg--you">
        <div class="ab-msg__who">
          Tarefa <span class="ab-data-sm">{Time.local_time(@task.inserted_at, @offset)}</span>
        </div>
        <p>{clean_body(@task.body)}</p>
      </div>

      <div
        :for={comment <- @comments}
        class={[
          "ab-msg",
          comment.kind == "agent" && "ab-msg--agent",
          comment.kind != "agent" && "ab-msg--you"
        ]}
      >
        <div class="ab-msg__who">
          {if comment.kind == "agent", do: comment.author || "Agente", else: "Você"}
          <span class="ab-data-sm">{Time.local_time(comment.inserted_at, @offset)}</span>
        </div>
        <p><.markup text={clean_body(comment.body)} /></p>
      </div>

      <div :if={@comments == [] and @task.body in [nil, ""]} class="ab-sec__empty">
        Sem conversa nesta tarefa.
      </div>

      <div :if={@comments == [] and @task.body not in [nil, ""]} class="ab-sec__empty">
        Nenhuma resposta ainda. O agente recebe a mensagem pelo GitHub.
      </div>
    </div>
    """
  end

  defp activity_tab(assigns) do
    ~H"""
    <div>
      <div :if={@activity == []} class="ab-sec__empty">Nenhuma atividade registrada.</div>
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
        Nenhuma chamada de IA registrada para esta tarefa.
      </div>

      <div
        :if={@calls != []}
        class="ab-table-wrap"
        tabindex="0"
        role="region"
        aria-label="Chamadas de IA"
      >
        <table class="ab-table">
          <thead>
            <tr>
              <th>Hora</th>
              <th>Modelo</th>
              <th class="r">Entrada</th>
              <th class="r">Saída</th>
              <th class="r">Tempo</th>
              <th class="r">Custo</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={call <- Enum.reverse(@calls)}>
              <td>{Time.local_time(call.inserted_at, @offset)}</td>
              <td>{call.model || "desconhecido"}</td>
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
        Chamadas feitas pelo board.
        <span :if={@totals.missing_cost}>Custo ausente aparece como —; o total é um mínimo.</span>
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
        Resultado da tarefa: <b>{task_result(@task, @pr)}</b>.
        <span :if={@executions == [] and @runner_executions == []}>
          Nenhuma execução desta tarefa no livro de uso.
        </span>
      </p>

      <section
        :if={@runner_executions != []}
        class="ab-runner-list"
        aria-labelledby="runner-list-title"
      >
        <h3 id="runner-list-title" class="ab-label">Despachos do board</h3>
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
              title="Preço de lista informado pela CLI; não é a fatura"
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
            <span :if={execution.session_id}>sessão {execution.session_id} · </span>
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
              <dt>Requisições</dt><dd>{execution.requests}</dd>
            </div>
            <div>
              <dt>Entrada</dt><dd>{tokens(execution.input_tokens)}</dd>
            </div>
            <div>
              <dt>Saída</dt><dd>{tokens(execution.output_tokens)}</dd>
            </div>
            <div>
              <dt>Custo</dt><dd>{execution_cost(execution)}</dd>
            </div>
          </dl>
        </li>
      </ol>

      <p :if={@executions != []} class="ab-meta">
        Tokens medidos. O custo é estimado na moeda de cada executor; "lista"
        é o preço de referência do Claude Max, não a fatura. O Codex não tem US$:
        a cota semanal fica no painel Executores. Uma sessão sem branch de PR
        nem vínculo direto não aparece como tarefa, e o livro não guarda o
        resultado de cada sessão.
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
    do: "Despachar para o #{AgentBoard.Executors.name(task.executor)}"

  # A dispatch belongs to a task that can still run: queued, blocked after a
  # failure, or already running. A task waiting for review or finished has
  # its result in Execuções, not another dispatch button.
  defp dispatchable?(task) do
    task.executor in ["claude", "codex"] and task.state in ["queued", "blocked", "running"] and
      not (task.stopped or task.archived)
  end

  defp runner_status("starting"), do: "iniciando"
  defp runner_status("running"), do: "rodando"
  defp runner_status("done"), do: "concluído"
  defp runner_status("failed"), do: "falhou"
  defp runner_status("stopped"), do: "parado"
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

  defp execution_cost(%{source: "codex"}), do: "desconhecido"
  defp execution_cost(%{cost: nil}), do: "desconhecido"

  defp execution_cost(%{source: "claude_code", cost: %{micros: micros, complete?: true}}),
    do: "≈ #{cost(micros)} lista"

  defp execution_cost(%{source: "claude_code", cost: %{micros: micros}}),
    do: "≥ #{cost(micros)} lista"

  defp execution_cost(%{cost: %{micros: micros, complete?: true}}), do: "≈ #{cost(micros)}"
  defp execution_cost(%{cost: %{micros: micros}}), do: "≥ #{cost(micros)}"

  @task_results %{
    "done" => "mesclado",
    "blocked" => "bloqueado",
    "question" => "pergunta",
    "ready" => "para revisar",
    "running" => "em andamento",
    "retrying" => "tentando de novo",
    "queued" => "na fila",
    "stopped" => "parado",
    "archived" => "arquivado",
    "closed" => "fechado sem merge"
  }

  defp task_result(task, pr) do
    word = Map.get(@task_results, task.state, "desconhecido")
    if pr, do: "#{word}, PR ##{pr.number}", else: word
  end

  attr :usage, :map, default: nil

  defp executor_usage(%{usage: nil} = assigns), do: ~H""

  defp executor_usage(%{usage: %{status: :none}} = assigns) do
    ~H"""
    <section id="executor-usage" class="ab-insp__usage">
      <h3 class="ab-label">Executor do agente</h3>
      <p class="ab-meta">Nenhuma transcrição do executor para esta tarefa.</p>
    </section>
    """
  end

  defp executor_usage(%{usage: %{status: :unavailable}} = assigns) do
    ~H"""
    <section id="executor-usage" class="ab-insp__usage">
      <h3 class="ab-label">Executor do agente</h3>
      <p class="ab-meta">
        As transcrições existem, mas o board não consegue lê-las: falta o <code>zstd</code>.
      </p>
    </section>
    """
  end

  defp executor_usage(assigns) do
    ~H"""
    <section id="executor-usage" class="ab-insp__usage">
      <h3 class="ab-label">Executor do agente</h3>
      <table class="ab-table">
        <thead>
          <tr>
            <th>Sessões</th>
            <th class="r">Requisições</th>
            <th class="r">Entrada</th>
            <th class="r">Saída</th>
            <th class="r">Cache lido</th>
            <th class="r">Custo estimado</th>
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
        Medido nas transcrições locais do executor ({models(@usage.models)}). O custo usa a tabela de preços do board.
        <span :if={@usage.cost && not @usage.cost.complete?}>
          Algum tipo de token não tem preço na tabela (a leitura de cache, hoje); o custo é um mínimo.
        </span>
        <span :if={@usage.cost == nil}>O modelo não tem preço na tabela; custo desconhecido.</span>
        <span :if={@usage.unreadable > 0}>
          {@usage.unreadable} {if @usage.unreadable == 1,
            do: "transcrição ilegível",
            else: "transcrições ilegíveis"}; os números são um mínimo.
        </span>
      </p>
    </section>
    """
  end

  defp sessions(%{workers: workers, subagents: 0}), do: "#{workers} worker"

  defp sessions(%{workers: workers, subagents: subagents}),
    do: "#{workers} worker + #{subagents} subagente(s)"

  defp models([]), do: "modelo desconhecido"
  defp models(models), do: Enum.join(models, ", ")

  defp usage_cost(nil), do: "—"
  defp usage_cost(%{micros: micros, complete?: true}), do: cost(micros)
  defp usage_cost(%{micros: micros, complete?: false}) when micros > 0, do: "≥ #{cost(micros)}"
  defp usage_cost(_), do: "—"

  defp pr_tab(assigns) do
    ~H"""
    <div>
      <div :if={is_nil(@pr)} class="ab-sec__empty">Esta tarefa ainda não abriu PR.</div>

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
        ><.ico name="ext" />Abrir no GitHub</a>
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

  defp pr_word(_pr, %{state: :fail}), do: "CI local falhou"
  defp pr_word(%{state: "merged"}, _ci), do: "Mesclado"
  defp pr_word(_pr, _ci), do: "Aberto"

  defp pr_ci(_pr, %{state: :pass}), do: "CI local ok"
  defp pr_ci(_pr, %{state: :fail}), do: "CI local falhou"
  defp pr_ci(_pr, %{state: :stale}), do: "CI local ?"
  defp pr_ci(%{checks_state: "failure"}, _ci), do: "CI local ?"
  defp pr_ci(%{checks_state: "success"}, _ci), do: "CI ok"
  defp pr_ci(%{checks_state: "none"}, _ci), do: "sem CI"
  defp pr_ci(_pr, _ci), do: "CI desconhecido"

  defp pr_ci_title(_pr, %{state: :pass, detail: detail, remote_blocked: true} = ci) do
    "GitHub Actions não rodou (billing/sem crédito). " <> local_scope(ci) <> detail
  end

  defp pr_ci_title(_pr, %{state: :pass, detail: detail} = ci),
    do: local_scope(ci) <> detail

  defp pr_ci_title(_pr, %{state: :fail, detail: detail}),
    do: "CI local falhou: #{detail}"

  defp pr_ci_title(_pr, %{state: :stale, detail: detail}), do: detail

  defp pr_ci_title(%{checks_state: "failure"}, _ci),
    do: "GitHub Actions falhou (billing/sem crédito); sem evidência de CI local."

  defp pr_ci_title(%{checks_state: "success"}, _ci), do: "GitHub Actions passou."
  defp pr_ci_title(_pr, _ci), do: "Nenhum check remoto configurado."

  defp local_scope(%{scope: :ticket, evidence_pr: number}),
    do: "CI local passou no ticket (relatório cita ##{number}); este PR é do mesmo trabalho: "

  defp local_scope(_ci), do: "CI local passou: "

  defp local_ci_pass?(%{state: :pass}), do: true
  defp local_ci_pass?(_ci), do: false

  defp pr_review("approved"), do: "revisado"
  defp pr_review("changes_requested"), do: "mudanças pedidas"
  defp pr_review("pending"), do: "revisão pendente"
  defp pr_review(_state), do: "sem revisão"

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
