defmodule AgentBoardWeb.BoardComponents.VoiceConversationLog do
  @moduledoc """
  The conversation with the agent, for when the owner wants to read it: the
  recent turns, a line to type instead of speaking, and a way to forget.

  Talking needs none of this (double Space, speak, stop); the log is the
  record, not a step.
  """
  use Phoenix.Component
  use Gettext, backend: AgentBoardWeb.Gettext

  attr :turns, :list, required: true
  attr :thinking, :boolean, default: false

  def log(assigns) do
    # Forgetting is red (no way back): the browser asks the registry's
    # sentence and the click carries it to the gate.
    assigns =
      assign(
        assigns,
        :forget_phrase,
        AgentBoard.Actions.phrase(:forget_conversation, %{}, AgentBoardWeb.Locale.language())
      )

    ~H"""
    <section class="voice-chat" aria-labelledby="voice-chat-heading">
      <div class="voice-chat-head">
        <h3 id="voice-chat-heading">{gettext("Agent conversation")}</h3>
        <button
          :if={@turns != []}
          id="voice-forget"
          type="button"
          phx-click="voice_forget"
          phx-value-confirm={@forget_phrase}
          data-confirm={@forget_phrase}
          class="voice-chat-forget"
        >
          {gettext("Forget conversation")}
        </button>
      </div>
      <p :if={@turns == []} class="voice-chat-empty">
        {gettext(
          "Press space twice, speak and stop: the agent responds in voice. It remembers the conversation, checks the board, and creates tasks after you confirm."
        )}
      </p>
      <ol
        :if={@turns != []}
        id="voice-chat-turns"
        class="voice-chat-turns"
        tabindex="0"
        aria-label={gettext("Voice conversation history")}
      >
        <%!-- Rendered newest first in a column-reverse list: the scroll stays
             anchored on the latest turn while reading top to bottom. --%>
        <li :for={turn <- Enum.reverse(@turns)} class="voice-chat-turn" data-role={turn.role}>
          <span class="voice-chat-who">{if turn.role == "owner",
            do: gettext("You"),
            else: gettext("Agent")}</span>
          <p>{turn.text}</p>
          <span :if={turn.role == "agent" && turn.duration_ms} class="voice-chat-time">
            {gettext("thought for %{time}", time: seconds(turn.duration_ms))}
          </span>
        </li>
      </ol>
      <p :if={@thinking} class="voice-chat-thinking" role="status">
        {gettext("The agent is thinking...")}
      </p>
      <form id="voice-chat-form" phx-submit="voice_turn" class="voice-chat-form">
        <label for="voice-chat-text" class="sr-only">{gettext("Write to agent")}</label>
        <input
          id="voice-chat-text"
          name="text"
          maxlength="2000"
          autocomplete="off"
          placeholder={gettext("Or type for the agent...")}
        />
        <button type="submit">{gettext("Send")}</button>
      </form>
    </section>
    """
  end

  defp seconds(ms), do: AgentBoardWeb.Numbers.decimal(ms / 1000, 1) <> " s"
end
