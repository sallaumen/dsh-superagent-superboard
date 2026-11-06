defmodule AgentBoardWeb.BoardComponents.Inspector do
  @moduledoc "The task inspector: conversation, activity, AI calls and PR, without leaving the board."
  use AgentBoardWeb, :html

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1, kbd: 1]
  import AgentBoardWeb.BoardComponents.Markup, only: [markup: 1]
  import AgentBoardWeb.BoardComponents.StatusMark, only: [status_mark: 1]

  alias AgentBoard.Time

  attr :task, :any, required: true
  attr :comments, :list, required: true
  attr :tab, :string, required: true
  attr :activity, :list, required: true
  attr :calls, :list, required: true
  attr :pr, :any, default: nil
  attr :tz_offset, :integer, default: 0
  attr :live, :boolean, default: false

  def inspector(assigns) do
    tabs = [
      {"conversa", "Conversa", length(assigns.comments)},
      {"atividade", "Atividade", length(assigns.activity)},
      {"chamadas", "Chamadas de IA", length(assigns.calls)},
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
          <span :if={@pr} class="ab-meta">PR #{@pr.number}</span>
          <span :if={@calls != []} class="ab-meta">{length(@calls)} chamadas</span>
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

        <div class="ab-insp__actions">
          <button
            :if={@task.stopped or @task.archived}
            type="button"
            class="ab-btn ab-btn--sm ab-btn--quiet"
            phx-click="act"
            phx-value-id={@task.id}
            phx-value-action="resume"
          >Retomar</button>
          <button
            :if={not (@task.stopped or @task.archived)}
            type="button"
            class="ab-btn ab-btn--sm ab-btn--halt"
            phx-click="act"
            phx-value-id={@task.id}
            phx-value-action="stop"
          >Parar</button>
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
            <.calls_tab calls={@calls} totals={@totals} offset={@tz_offset} />
          <% "pr" -> %>
            <.pr_tab pr={@pr} offset={@tz_offset} />
          <% _ -> %>
            <.conversation_tab task={@task} comments={@comments} offset={@tz_offset} />
        <% end %>
      </div>

      <div :if={@tab == "conversa"} class="ab-insp__foot">
        <form id="ask-agent" phx-submit="ask">
          <div class="ab-compose ab-compose--inline">
            <textarea
              id="ask-body"
              name="body"
              rows="2"
              aria-label="Mensagem para o agente"
              placeholder="Responder ao agente…"
              required
            ></textarea>
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

  defp conversation_tab(assigns) do
    ~H"""
    <div class="ab-conversation">
      <div :if={@task.body not in [nil, ""]} class="ab-msg ab-msg--you">
        <div class="ab-msg__who">
          Tarefa <span class="ab-data-sm">{Time.local_time(@task.inserted_at, @offset)}</span>
        </div>
        <p>{@task.body}</p>
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
        <p><.markup text={comment.body} /></p>
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

      <table :if={@calls != []} class="ab-table">
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

      <p :if={@calls != []} class="ab-meta">
        Chamadas feitas pelo board. O executor mantém as dele fora do board.
        <span :if={@totals.missing_cost}>Custo ausente aparece como —; o total é um mínimo.</span>
      </p>
    </div>
    """
  end

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
          <.status_mark kind={pr_kind(@pr)} word={pr_word(@pr)} />
          <span :if={@pr.merged_at} class="ab-meta">
            mesclado às {Time.local_time(@pr.merged_at, @offset)}
          </span>
          <span class="ab-meta">{pr_ci(@pr)}</span>
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
  defp status_kind("queued"), do: :queue
  defp status_kind("done"), do: :done
  defp status_kind("stopped"), do: :queue
  defp status_kind("archived"), do: :queue
  defp status_kind(_state), do: :unknown

  defp status_word("stopped"), do: "Parado"
  defp status_word("archived"), do: "Arquivado"
  defp status_word(_state), do: nil

  defp pr_kind(%{checks_state: "failure"}), do: :cifail
  defp pr_kind(%{state: "merged"}), do: :done
  defp pr_kind(_pr), do: :review

  defp pr_word(%{checks_state: "failure"}), do: "CI falhou"
  defp pr_word(%{state: "merged"}), do: "Mesclado"
  defp pr_word(_pr), do: "Aberto"

  defp pr_ci(%{checks_state: "failure"} = pr),
    do: "CI falhou" <> if(pr.checks_failed in [nil, ""], do: "", else: " · #{pr.checks_failed}")

  defp pr_ci(%{checks_state: "success"}), do: "CI ok"
  defp pr_ci(%{checks_state: "none"}), do: "sem CI"
  defp pr_ci(_pr), do: "CI desconhecido"

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
