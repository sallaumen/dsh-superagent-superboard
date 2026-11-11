defmodule AgentBoardWeb.BoardComponents.MessageHub do
  @moduledoc "Two compact header windows: agent conversations and operational attention."
  use AgentBoardWeb, :html

  alias AgentBoardWeb.Time

  attr :messages, :list, default: []
  attr :alerts, :list, default: []
  attr :seen, :map, default: %{}
  attr :filter, :string, default: "all"
  attr :notice, :string, default: nil
  slot :inner_block, doc: "a mark that sits first in the row, such as the peak hours"

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
    <div class="ab-message-hub" aria-label={gettext("Messages and notifications")}>
      {render_slot(@inner_block)}
      <details id="message-inbox" class="ab-hub-menu" data-board-menu phx-hook="BoardMenu">
        <summary aria-label={message_label(@unread)} title={gettext("Messages from Yasme")}>
          <.icon name="hero-chat-bubble-left-right" class="size-5" />
          <span class="ab-hub-menu__name">{gettext("Messages")}</span>
          <span :if={@unread > 0} class="ab-hub-menu__count" aria-hidden="true">{count(@unread)}</span>
        </summary>
        <div class="ab-hub-menu__popover">
          <header class="ab-hub-menu__heading">
            <div>
              <strong>{gettext("Messages")}</strong>
              <p>{gettext("Yasme's replies, by task")}</p>
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
            <div
              class="ab-segmented ab-segmented--sm ab-hub-menu__filters"
              role="group"
              aria-label={gettext("Filter messages")}
            >
              <button
                type="button"
                class="ab-segment"
                phx-click="filter_inbox"
                phx-value-filter="all"
                aria-pressed={to_string(@filter == "all")}
              >{gettext("All")}</button>
              <button
                type="button"
                class="ab-segment"
                phx-click="filter_inbox"
                phx-value-filter="unread"
                aria-pressed={to_string(@filter == "unread")}
              >{gettext("Unread")}</button>
            </div>
            <button
              type="button"
              class="ab-hub-menu__mark-all"
              phx-click="mark_messages_seen"
              phx-disable-with={gettext("Marking…")}
              disabled={@unread == 0}
            >
              {gettext("Mark all as seen")}
            </button>
          </div>
          <p :if={@notice} class="ab-hub-menu__notice" role="alert">{@notice}</p>
          <p :if={@messages == []} class="ab-hub-menu__empty">
            {gettext("No replies yet. Conversations appear here when Yasme answers.")}
          </p>
          <p :if={@messages != [] and @visible_messages == []} class="ab-hub-menu__empty">
            {gettext("You are up to date. New replies appear here.")}
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
                    <span :if={unread?(item, @seen)} class="ab-hub-item__new">{gettext("New")} · </span>
                    {age(item.at)}
                  </time>
                </span>
                <strong>#{item.number} · {item.title}</strong>
                <span class="ab-hub-item__preview">{item.preview}</span>
                <span class="ab-hub-item__action">
                  {gettext("Open conversation")} <span aria-hidden="true">→</span>
                </span>
              </button>
              <button
                :if={unread?(item, @seen)}
                type="button"
                class="ab-hub-row__read"
                phx-click="mark_inbox_message_seen"
                phx-value-id={item.task_id}
                phx-value-version={item.version}
                phx-disable-with={gettext("Marking…")}
                aria-label={gettext("Mark the reply on task #%{number} as seen", number: item.number)}
                title={gettext("Mark as seen without opening the conversation")}
              >
                <.icon name="hero-check" class="size-4" />
                <span>{gettext("Mark seen")}</span>
              </button>
            </li>
          </ol>
          <p class="ab-hub-menu__foot">
            {gettext("Up to 30 recent conversations · updates on its own.")}
          </p>
        </div>
      </details>

      <details id="attention-inbox" class="ab-hub-menu" data-board-menu phx-hook="BoardMenu">
        <summary aria-label={alert_label(length(@alerts))} title={gettext("General notifications")}>
          <.icon name="hero-bell" class="size-5" />
          <span class="ab-hub-menu__name">{gettext("Attention")}</span>
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
              <strong>{gettext("Needs you")}</strong>
              <p>{gettext("Open items from every project")}</p>
            </div>
          </header>
          <p :if={@alerts == []} class="ab-hub-menu__empty">
            {gettext("Nothing is waiting for you now.")}
          </p>
          <ol :if={@alerts != []} class="ab-hub-menu__list">
            <li :for={item <- @alerts}>
              <button
                type="button"
                class="ab-hub-item"
                phx-click="open_inbox_task"
                phx-value-id={item.task_id}
                data-board-menu-link
                aria-label={
                  gettext("Open task #%{number} in %{repo}: %{kind}",
                    number: item.number,
                    repo: item.repo,
                    kind: alert_kind(item.state)
                  )
                }
              >
                <span class="ab-hub-item__meta"><span>{item.repo}</span><span>{alert_kind(item.state)}</span></span>
                <strong>#{item.number} · {item.title}</strong>
                <span class="ab-hub-item__action">
                  {gettext("View task")} <span aria-hidden="true">→</span>
                </span>
              </button>
            </li>
          </ol>
          <p class="ab-hub-menu__foot">
            {gettext("The number counts open items, not unread messages.")}
          </p>
        </div>
      </details>
    </div>
    """
  end

  defp unread?(item, seen),
    do: item.version != Map.get(seen, Integer.to_string(item.task_id))

  defp message_item_label(item, seen) do
    open =
      gettext("Open the conversation on task #%{number} in %{repo}",
        number: item.number,
        repo: item.repo
      )

    if unread?(item, seen), do: gettext("New reply.") <> " " <> open, else: open
  end

  defp unread_text(0), do: gettext("All seen")
  defp unread_text(n), do: ngettext("%{count} new", "%{count} new", n)

  defp count(n) when n > 99, do: "99+"
  defp count(n), do: n
  defp message_label(0), do: gettext("Messages from Yasme, none new")

  defp message_label(n),
    do: ngettext("Messages from Yasme, %{count} new", "Messages from Yasme, %{count} new", n)

  defp alert_label(0), do: gettext("Attention, nothing open")

  defp alert_label(n),
    do: ngettext("Attention, %{count} open item", "Attention, %{count} open items", n)

  defp alert_kind("blocked"), do: pgettext("attention kind", "Blocked")
  defp alert_kind("question"), do: pgettext("attention kind", "Question")
  defp alert_kind("ready"), do: pgettext("attention kind", "Review")
  defp alert_kind("slow"), do: pgettext("attention kind", "Taking long")

  defp age(at), do: at |> then(&DateTime.diff(DateTime.utc_now(), &1)) |> max(0) |> Time.ago()
end
