defmodule AgentBoardWeb.BoardComponents.MessageHub do
  @moduledoc "Two compact header windows: agent conversations and operational attention."
  use AgentBoardWeb, :html

  alias AgentBoard.Time

  attr :messages, :list, default: []
  attr :alerts, :list, default: []
  attr :seen, :map, default: %{}

  def hub(assigns) do
    assigns = assign(assigns, :unread, Enum.count(assigns.messages, &unread?(&1, assigns.seen)))

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
            <span :if={@unread > 0} class="ab-hub-menu__new">{@unread} novas</span>
          </header>
          <p :if={@messages == []} class="ab-hub-menu__empty">
            Nenhuma resposta registrada. As conversas aparecerão aqui quando a Yasme responder.
          </p>
          <ol :if={@messages != []} class="ab-hub-menu__list">
            <li :for={item <- @messages}>
              <button
                type="button"
                class={["ab-hub-item", unread?(item, @seen) && "is-unread"]}
                phx-click="open_inbox_task"
                phx-value-id={item.task_id}
                data-board-menu-link
                aria-label={"Abrir conversa da tarefa ##{item.number} em #{item.repo}"}
              >
                <span class="ab-hub-item__meta">
                  <span>{item.repo}</span>
                  <time
                    datetime={DateTime.to_iso8601(item.at)}
                    title={Calendar.strftime(item.at, "%d/%m/%Y %H:%M UTC")}
                  >
                    Resposta · {age(item.at)}
                  </time>
                </span>
                <strong>#{item.number} · {item.title}</strong>
                <span class="ab-hub-item__preview">{item.preview}</span>
                <span class="ab-hub-item__action">Abrir conversa <span aria-hidden="true">→</span></span>
              </button>
            </li>
          </ol>
          <p class="ab-hub-menu__foot">A lista se atualiza quando uma resposta chega ao board.</p>
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
