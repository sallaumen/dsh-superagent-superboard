defmodule AgentBoardWeb.BoardComponents.Voice.ConversationLog do
  @moduledoc "The board's Chat: its persistent turns, skills and message composer."
  use Phoenix.Component
  use Gettext, backend: AgentBoardWeb.Gettext

  import AgentBoardWeb.BoardComponents.Controls, only: [ico: 1]
  import AgentBoardWeb.BoardComponents.Markup, only: [markup: 1]

  alias AgentBoardWeb.BoardComponents.Voice.CommandList
  alias AgentBoardWeb.Time

  attr :turns, :list, required: true
  attr :thinking, :boolean, default: false
  attr :input, :string, required: true
  attr :language, :string, required: true
  attr :commands_open, :boolean, default: false
  attr :tz_offset, :integer, default: 0

  def log(assigns) do
    assigns =
      assign(
        assigns,
        :forget_phrase,
        AgentBoard.Actions.phrase(:forget_conversation, %{}, AgentBoardWeb.Locale.language())
      )

    ~H"""
    <div class="sb-chat">
      <ol
        :if={@turns != []}
        id="voice-chat-turns"
        class="sb-chat__history"
        phx-hook="ChatHistory"
        tabindex="0"
        aria-label={gettext("Chat history")}
      >
        <li
          :for={turn <- @turns}
          id={"chat-turn-#{turn.id}"}
          data-role={turn.role}
          class={["ab-msg", if(turn.role == "owner", do: "ab-msg--you", else: "ab-msg--agent")]}
        >
          <div class="ab-msg__who">
            {if turn.role == "owner", do: gettext("You"), else: gettext("Agent")}
            <time class="ab-data-sm" datetime={DateTime.to_iso8601(turn.inserted_at)}>
              {Time.local_time(turn.inserted_at, @tz_offset)}
            </time>
          </div>
          <p><.markup text={turn.text} links /></p>
          <span :if={turn.role == "agent" && turn.duration_ms} class="voice-chat-time">
            {gettext("thought for %{time}", time: seconds(turn.duration_ms))}
          </span>
        </li>
      </ol>
      <p :if={@thinking} class="voice-chat-thinking" role="status">
        {gettext("The agent is thinking...")}
      </p>
      <CommandList.list open={@commands_open} language={@language} featured={@turns == []} />
      <form id="voice-chat-form" phx-submit="voice_chat_send" class="sb-chat__form">
        <label for="voice-chat-text" class="sr-only">{gettext("Write to agent")}</label>
        <%!-- The draft belongs to this tab, even when a skill takes focus during a reply. --%>
        <input
          id="voice-chat-text"
          phx-update="ignore"
          name="text"
          maxlength="2000"
          autocomplete="off"
          required
          placeholder={gettext("Ask about your board…")}
        />
        <button
          :if={@input != "text"}
          type="button"
          class="ab-btn ab-btn--icon"
          phx-click={Phoenix.LiveView.JS.dispatch("board:voice-start")}
          title={gettext("Dictate by voice")}
          aria-label={gettext("Dictate by voice")}
        >
          <.ico name="mic" />
        </button>
        <button type="submit" class="ab-btn ab-btn--primary" aria-label={gettext("Send")}>
          <.ico name="send" />
        </button>
      </form>
      <button
        :if={@turns != []}
        id="voice-forget"
        type="button"
        phx-click="voice_forget"
        phx-value-confirm={@forget_phrase}
        data-confirm={@forget_phrase}
        class="sb-chat__forget"
      >
        {gettext("Forget conversation")}
      </button>
    </div>
    """
  end

  defp seconds(ms), do: AgentBoardWeb.Numbers.decimal(ms / 1000, 1) <> " s"
end
