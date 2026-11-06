defmodule AgentBoardWeb.BoardComponents.Composer do
  @moduledoc "The request layer: write or dictate, split with review, then enqueue."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1, kbd: 1]

  attr :repo, :string, required: true
  attr :text, :string, default: ""
  attr :split, :boolean, default: false
  attr :intake, :any, default: nil
  attr :selected, :any, default: nil
  attr :ai_status, :any, default: :logged_in
  attr :voice_configured, :boolean, default: false
  attr :error, :string, default: nil

  def composer(assigns) do
    tasks = (assigns.intake && assigns.intake.tasks) || []
    status = assigns.intake && Map.get(assigns.intake, :status)
    questions = (assigns.intake && get_in(assigns.intake.spec, ["open_questions"])) || []
    selected = assigns.selected || MapSet.new(Enum.to_list(0..max(length(tasks) - 1, 0)))

    assigns =
      assigns
      |> assign(:tasks, tasks)
      |> assign(:status, status)
      |> assign(:questions, questions)
      |> assign(:selected, selected)
      |> assign(:selected_count, Enum.count(selected, &(&1 in 0..max(length(tasks) - 1, 0))))

    ~H"""
    <div class="ab-compose" data-composer>
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

      <p :if={@error} class="ab-compose__error" role="alert">{@error}</p>

      <form id="composer-form" phx-change="composer_change" phx-submit="composer_submit">
        <textarea
          id="composer-text"
          name="text"
          aria-label="Descreva o pedido"
          placeholder="Descreva o que o agente deve fazer. Pode colar um issue, um erro ou falar."
          phx-hook="Composer"
          autofocus
        >{@text}</textarea>

        <div :if={@split && !is_nil(@intake)} class="ab-sec__head ab-compose__split-head">
          <span class="ab-label">
            {if @tasks == [],
              do: "A IA não propôs tarefas",
              else: "Vai virar #{length(@tasks)} tarefas, nesta ordem"}
          </span>
        </div>

        <div :if={@split && !is_nil(@intake) && @status == :needs_clarification} class="ab-split-note">
          <p class="ab-meta">A IA ainda tem perguntas antes de dividir:</p>
          <ul>
            <li :for={question <- @questions}>{question}</li>
          </ul>
          <p class="ab-meta">Edite o pedido e divida de novo.</p>
        </div>

        <div :if={@split && @tasks != []} class="ab-split">
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
            disabled={not @voice_configured}
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
            disabled={@ai_status == :not_configured}
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
            phx-disable-with="Enviando…"
            disabled={String.trim(@text) == "" or (@split and @tasks != [] and @selected_count == 0)}
          >
            {button_label(@split, @tasks, @selected_count)}<.kbd key="⌘↵" />
          </button>
        </div>
      </form>
    </div>
    """
  end

  defp button_label(false, _tasks, _count), do: "Pôr na fila"
  defp button_label(true, [], _count), do: "Dividir pedido"
  defp button_label(true, _tasks, count), do: "Pôr #{count} na fila"
end
