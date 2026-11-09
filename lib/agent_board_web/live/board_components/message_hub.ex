defmodule AgentBoardWeb.BoardComponents.MessageHub do
  @moduledoc "Two compact header windows: agent conversations and operational attention."
  use AgentBoardWeb, :html

  alias AgentBoard.Time

  attr :messages, :list, default: []
  attr :alerts, :list, default: []
  attr :seen, :map, default: %{}
  attr :filter, :string, default: "all"
  attr :notice, :string, default: nil

  def hub(assigns) do
    unread_messages = Enum.filter(assigns.messages, &unread?(&1, assigns.seen))

    assigns =
      assigns
      |> assign(:unread, length(unread_messages))
      |> assign(
        :visible_messages,
        if(assigns.filter == "unread", do: unread_messages, else: assigns.messages)
      )

    ~H"""
    <div class="ab-message-hub" aria-label="Mensagens e notificações">
      <details id="message-inbox" class="ab-hub-menu" data-board-menu phx-hook="BoardMenu">
        <summary aria-label={message_label(@unread)} title="Mensagens da Yasme">
          <.icon name="hero-chat-bubble-left-right" class="size-5" />
          <span class="ab-hub-menu__name">Mensagens</span>
          <span :if={@unread > 0} class="ab-hub-menu__count" aria-hidden="true">{count(@unread)}</span>
        </summary>
        <div class="ab-hub-menu__popover">
          <header class="ab-hub-menu__heading">
            <div>
              <strong>Mensagens</strong><p>Respostas da Yasme por tarefa</p>
            </div>
            <span
              class={["ab-hub-menu__new", @unread == 0 && "is-clear"]}
              role="status"
              aria-live="polite"
            >
              {unread_text(@unread)}
            </span>
          </header>
          <div :if={@messages != []} class="ab-hub-menu__tools">
            <div class="ab-hub-menu__filters" role="group" aria-label="Filtrar mensagens">
              <button
                type="button"
                phx-click="filter_inbox"
                phx-value-filter="all"
                aria-pressed={to_string(@filter == "all")}
              >Todas</button>
              <button
                type="button"
                phx-click="filter_inbox"
                phx-value-filter="unread"
                aria-pressed={to_string(@filter == "unread")}
              >Não lidas</button>
            </div>
            <button
              type="button"
              class="ab-hub-menu__mark-all"
              phx-click="mark_messages_seen"
              phx-disable-with="Marcando…"
              disabled={@unread == 0}
            >
              Marcar todas como vistas
            </button>
          </div>
          <p :if={@notice} class="ab-hub-menu__notice" role="alert">{@notice}</p>
          <p :if={@messages == []} class="ab-hub-menu__empty">
            Nenhuma resposta registrada. As conversas aparecerão aqui quando a Yasme responder.
          </p>
          <p :if={@messages != [] and @visible_messages == []} class="ab-hub-menu__empty">
            Você está em dia. Novas respostas aparecerão aqui.
          </p>
          <ol :if={@visible_messages != []} class="ab-hub-menu__list">
            <li :for={item <- @visible_messages} class={unread?(item, @seen) && "has-quick-read"}>
              <button
                type="button"
                class={["ab-hub-item", unread?(item, @seen) && "is-unread"]}
                phx-click="open_inbox_task"
                phx-value-id={item.task_id}
                data-board-menu-link
                aria-label={message_item_label(item, @seen)}
              >
                <span class="ab-hub-item__meta">
                  <span class="ab-hub-item__project" title={item.repo}>{item.repo}</span>
                  <time
                    class="ab-hub-item__time"
                    datetime={DateTime.to_iso8601(item.at)}
                    title={Calendar.strftime(item.at, "%d/%m/%Y %H:%M UTC")}
                  >
                    <span :if={unread?(item, @seen)} class="ab-hub-item__new">Nova · </span>
                    {age(item.at)}
                  </time>
                </span>
                <strong>#{item.number} · {item.title}</strong>
                <span class="ab-hub-item__preview">{item.preview}</span>
                <span class="ab-hub-item__action">Abrir conversa <span aria-hidden="true">→</span></span>
              </button>
              <button
                :if={unread?(item, @seen)}
                type="button"
                class="ab-hub-row__read"
                phx-click="mark_inbox_message_seen"
                phx-value-id={item.task_id}
                phx-value-version={item.version}
                phx-disable-with="Marcando…"
                aria-label={"Marcar resposta da tarefa ##{item.number} como vista"}
                title="Marcar como vista sem abrir a conversa"
              >
                <.icon name="hero-check" class="size-4" />
                <span>Marcar vista</span>
              </button>
            </li>
          </ol>
          <p class="ab-hub-menu__foot">Até 30 conversas recentes · atualização automática.</p>
        </div>
      </details>

      <details id="attention-inbox" class="ab-hub-menu" data-board-menu phx-hook="BoardMenu">
        <summary aria-label={alert_label(length(@alerts))} title="Notificações gerais">
          <.icon name="hero-bell" class="size-5" />
          <span class="ab-hub-menu__name">Atenção</span>
          <span
            :if={@alerts != []}
            class="ab-hub-menu__count ab-hub-menu__count--attention"
            aria-hidden="true"
          >
            {count(length(@alerts))}
          </span>
        </summary>
        <div class="ab-hub-menu__popover">
          <header class="ab-hub-menu__heading">
            <div>
              <strong>Precisa de você</strong><p>Pendências de todos os projetos</p>
            </div>
          </header>
          <p :if={@alerts == []} class="ab-hub-menu__empty">Nada esperando sua atenção agora.</p>
          <ol :if={@alerts != []} class="ab-hub-menu__list">
            <li :for={item <- @alerts}>
              <button
                type="button"
                class="ab-hub-item"
                phx-click="open_inbox_task"
                phx-value-id={item.task_id}
                data-board-menu-link
                aria-label={"Abrir #{alert_kind(item.state)} da tarefa ##{item.number} em #{item.repo}"}
              >
                <span class="ab-hub-item__meta"><span>{item.repo}</span><span>{alert_kind(item.state)}</span></span>
                <strong>#{item.number} · {item.title}</strong>
                <span class="ab-hub-item__action">Ver tarefa <span aria-hidden="true">→</span></span>
              </button>
            </li>
          </ol>
          <p class="ab-hub-menu__foot">O número mostra pendências ativas, não mensagens não lidas.</p>
        </div>
      </details>
    </div>
    """
  end

  defp unread?(item, seen),
    do: item.version != Map.get(seen, Integer.to_string(item.task_id))

  defp message_item_label(item, seen) do
    prefix = if unread?(item, seen), do: "Nova resposta. ", else: ""
    "#{prefix}Abrir conversa da tarefa ##{item.number} em #{item.repo}"
  end

  defp unread_text(0), do: "Tudo visto"
  defp unread_text(1), do: "1 nova"
  defp unread_text(n), do: "#{n} novas"

  defp count(n) when n > 99, do: "99+"
  defp count(n), do: n
  defp message_label(0), do: "Mensagens da Yasme, nenhuma nova"
  defp message_label(1), do: "Mensagens da Yasme, 1 nova"
  defp message_label(n), do: "Mensagens da Yasme, #{n} novas"
  defp alert_label(0), do: "Atenção, nenhuma pendência"
  defp alert_label(1), do: "Atenção, 1 pendência ativa"
  defp alert_label(n), do: "Atenção, #{n} pendências ativas"
  defp alert_kind("blocked"), do: "Bloqueio"
  defp alert_kind("question"), do: "Pergunta"
  defp alert_kind("ready"), do: "Revisão"

  defp age(at), do: at |> then(&DateTime.diff(DateTime.utc_now(), &1)) |> max(0) |> Time.ago()
end
