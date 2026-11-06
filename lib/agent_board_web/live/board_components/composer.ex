defmodule AgentBoardWeb.BoardComponents.Composer do
  @moduledoc """
  The request layer: write or dictate, split with review, then enqueue.

  The panel is a view of one explicit lifecycle owned by `BoardLive`: a
  draft, a job in flight (`splitting` or `enqueuing`), a proposal to review
  (`ready`, `needs_clarification`, `no_tasks`), a failure with a retry, and
  a receipt that names what was created. The receipt is read from the tasks
  the board stored, so a reload shows the same thing.
  """
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1, kbd: 1]

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

    ~H"""
    <div
      class="ab-compose"
      data-composer
      data-composer-state={state(@job, @receipt, @status, @error)}
    >
      <h2 id="composer-title" class="ab-sr">Novo pedido</h2>

      <div class="ab-compose__head">
        <span class="ab-label">Novo pedido em</span>
        <span class="ab-chip">{@repo}</span>
        <span class="ab-top__spacer"></span>
        <.kbd key="Esc" />
        <button
          type="button"
          class="ab-btn ab-btn--icon ab-btn--sm"
          phx-click="close"
          aria-label="Fechar (Esc)"
        >
          <.ico name="close" />
        </button>
      </div>

      <.receipt :if={@receipt} receipt={@receipt} />

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
            Tentar de novo
          </button>
        </p>

        <textarea
          id="composer-text"
          name="text"
          aria-label="Descreva o pedido"
          aria-describedby={@error && "composer-error"}
          placeholder="Descreva o que o agente deve fazer. Pode colar um issue, um erro ou falar."
          phx-hook="Composer"
          autofocus
        >{@text}</textarea>

        <div :if={!@split and String.trim(@text) != ""} class="ab-compose__title">
          <label for="composer-issue-title" class="ab-label">Título da issue</label>
          <input
            id="composer-issue-title"
            name="title"
            type="text"
            maxlength="120"
            value={@title || @derived_title}
            aria-describedby="composer-title-hint"
          />
          <span id="composer-title-hint" class="ab-meta">
            {if @title, do: "Editado por você.", else: "Da primeira frase do pedido; edite se quiser."}
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
            Cancelar
          </button>
        </p>

        <div :if={@split && !is_nil(@intake) && !@busy} class="ab-sec__head ab-compose__split-head">
          <span class="ab-label">{split_head(@status, @tasks)}</span>
        </div>

        <div :if={@split && @status == :needs_clarification && !@busy} class="ab-split-note">
          <p :if={@questions != []} class="ab-meta">A IA ainda tem perguntas antes de dividir:</p>
          <ul :if={@questions != []}>
            <li :for={question <- @questions}>{question}</li>
          </ul>
          <p :if={@questions == [] and @risks != []} class="ab-meta">
            A IA achou o pedido ambíguo e apontou estes riscos:
          </p>
          <ul :if={@questions == [] and @risks != []}>
            <li :for={risk <- @risks}>{risk}</li>
          </ul>
          <label for="composer-answers" class="ab-label">Responda aqui</label>
          <textarea
            id="composer-answers"
            name="answers"
            rows="3"
            placeholder="Suas respostas entram no pedido e a IA divide de novo."
          >{@answers}</textarea>
          <p class="ab-meta">Ou edite o pedido acima e divida de novo.</p>
        </div>

        <div :if={@split && @status == :no_tasks && !@busy} class="ab-split-note">
          <p class="ab-meta">
            A IA não propôs nenhuma tarefa utilizável para este pedido. Tente de novo ou envie como um pedido único.
          </p>
          <button type="button" class="ab-btn ab-btn--sm" phx-click="composer_single">
            Enviar como pedido único
          </button>
        </div>

        <div :if={@split && @tasks != [] && !@busy} class="ab-split">
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
            <span class="ab-meta">{task.size}</span>
          </label>
        </div>

        <div class="ab-compose__bar">
          <button
            type="button"
            class="ab-btn ab-btn--icon ab-btn--sm"
            aria-label="Ditar por voz"
            phx-click={JS.dispatch("board:voice-start")}
            disabled={not @voice_configured or @busy}
            title={
              if @voice_configured, do: "Ditar por voz", else: "A transcrição não está configurada"
            }
          >
            <.ico name="mic" />
          </button>

          <span id="composer-voice" class="ab-voice" data-phase="idle" hidden>
            <span class="ab-level" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i></span>
            <span data-voice-label>Ouvindo…</span>
            <button
              type="button"
              class="ab-btn ab-btn--icon ab-btn--sm ab-btn--quiet"
              aria-label="Parar de ouvir"
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
                do: "A IA não está configurada",
                else: "Dividir em tarefas"
            }
          >
            <span class="ab-toggle__track"></span>Dividir em tarefas
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

  attr :receipt, :map, required: true

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
          <span class="ab-receipt__title">{item.title}</span>
          <span class={["ab-tag", outcome_class(item.outcome)]}>{outcome_label(item.outcome)}</span>
          <span :if={item.task} class="ab-receipt__links">
            <a
              :if={item.task.url}
              class="ab-btn ab-btn--sm ab-btn--quiet"
              href={item.task.url}
              target="_blank"
              rel="noopener noreferrer"
            >
              Abrir issue<span class="ab-sr"> (abre o GitHub em nova aba)</span>
            </a>
            <button
              type="button"
              class="ab-btn ab-btn--sm ab-btn--quiet"
              phx-click="open"
              phx-value-id={item.task.id}
            >
              Ver no board
            </button>
          </span>
        </li>
      </ul>
      <div class="ab-receipt__actions">
        <button
          :if={@failed > 0}
          type="button"
          class="ab-btn ab-btn--sm ab-btn--primary"
          phx-click="composer_retry"
        >
          Tentar as {@failed} que falharam
        </button>
        <button type="button" class="ab-btn ab-btn--sm" phx-click="composer_reset">
          Novo pedido
        </button>
        <button type="button" class="ab-btn ab-btn--sm ab-btn--quiet" phx-click="close">
          Fechar
        </button>
      </div>
    </section>
    """
  end

  defp receipt_head(0, 0, failed),
    do: "Nada entrou na fila: #{failed} #{plural(failed, "falhou", "falharam")}."

  defp receipt_head(created, existing, 0) do
    [
      created > 0 && "#{created} #{plural(created, "pedido", "pedidos")} na fila",
      existing > 0 && "#{existing} já #{plural(existing, "estava", "estavam")} na fila"
    ]
    |> Enum.filter(& &1)
    |> Enum.join("; ")
    |> Kernel.<>(".")
  end

  defp receipt_head(created, existing, failed) do
    done = created + existing

    "#{done} de #{done + failed} na fila; #{failed} #{plural(failed, "falhou", "falharam")}."
  end

  defp receipt_number(%{task: %{number: number}}) when is_integer(number), do: "##{number}"
  defp receipt_number(_item), do: "—"

  defp outcome_label(:created), do: "na fila"
  defp outcome_label(:existing), do: "já estava na fila"
  defp outcome_label({:error, reason}), do: "falhou: " <> failure_reason(reason)

  defp outcome_class(:created), do: "ab-tag--agent"
  defp outcome_class(:existing), do: nil
  defp outcome_class({:error, _}), do: "ab-tag--halt"

  @doc "The human reason for a failed creation."
  def failure_reason(%{__exception__: true} = exception),
    do: exception |> Exception.message() |> String.slice(0, 120)

  def failure_reason(:conflict), do: "a issue já existia com outro número"
  def failure_reason(reason), do: reason |> inspect() |> String.slice(0, 120)

  defp state(job, _receipt, _status, _error) when not is_nil(job), do: to_string(job.kind)
  defp state(_job, receipt, _status, _error) when not is_nil(receipt), do: "receipt"
  defp state(_job, _receipt, _status, error) when not is_nil(error), do: "failed"
  defp state(_job, _receipt, nil, _error), do: "draft"
  defp state(_job, _receipt, status, _error), do: to_string(status)

  defp job_label(%{kind: :split}), do: "Dividindo o pedido em tarefas com a IA…"
  defp job_label(%{kind: :enqueue, total: 1}), do: "Criando a issue no GitHub…"
  defp job_label(%{kind: :enqueue, total: n}), do: "Criando #{n} issues no GitHub…"
  defp job_label(_job), do: "Trabalhando…"

  defp split_head(:ready, tasks), do: "Vai virar #{length(tasks)} tarefas, nesta ordem"
  defp split_head(:needs_clarification, _tasks), do: "A IA precisa de respostas antes de dividir"
  defp split_head(:no_tasks, _tasks), do: "A IA não propôs tarefas"
  defp split_head(_status, _tasks), do: ""

  defp submit_disabled?(_text, _split, _status, _count, true), do: true
  defp submit_disabled?(text, false, _status, _count, _busy), do: String.trim(text) == ""
  defp submit_disabled?(text, true, nil, _count, _busy), do: String.trim(text) == ""
  defp submit_disabled?(_text, true, :ready, count, _busy), do: count == 0
  defp submit_disabled?(_text, true, _status, _count, _busy), do: false

  defp button_label(false, _status, _count), do: "Pôr na fila"
  defp button_label(true, :ready, count), do: "Pôr #{count} na fila"
  defp button_label(true, :needs_clarification, _count), do: "Dividir com as respostas"
  defp button_label(true, _status, _count), do: "Dividir pedido"

  defp disable_label(false, _status), do: "Enviando…"
  defp disable_label(true, :ready), do: "Enviando…"
  defp disable_label(true, _status), do: "Dividindo…"

  defp plural(1, singular, _plural), do: singular
  defp plural(_n, _singular, plural), do: plural
end
