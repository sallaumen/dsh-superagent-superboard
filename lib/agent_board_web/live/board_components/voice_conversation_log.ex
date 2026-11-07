defmodule AgentBoardWeb.BoardComponents.VoiceConversationLog do
  @moduledoc """
  The conversation with the agent, for when the owner wants to read it: the
  recent turns, a line to type instead of speaking, and a way to forget.

  Talking needs none of this (double Space, speak, stop); the log is the
  record, not a step.
  """
  use Phoenix.Component

  attr :turns, :list, required: true
  attr :thinking, :boolean, default: false

  def log(assigns) do
    ~H"""
    <section class="voice-chat" aria-labelledby="voice-chat-heading">
      <div class="voice-chat-head">
        <h3 id="voice-chat-heading">Conversa com o agente</h3>
        <button
          :if={@turns != []}
          id="voice-forget"
          type="button"
          phx-click="voice_forget"
          data-confirm="Esquecer toda a conversa? O agente perde o contexto."
          class="voice-chat-forget"
        >
          Esquecer conversa
        </button>
      </div>
      <p :if={@turns == []} class="voice-chat-empty">
        Aperte espaço duas vezes, fale e pare: o agente responde em voz. Ele lembra
        da conversa, consulta o quadro e cria tarefas depois de você confirmar.
      </p>
      <ol :if={@turns != []} id="voice-chat-turns" class="voice-chat-turns">
        <%!-- Rendered newest first in a column-reverse list: the scroll stays
             anchored on the latest turn while reading top to bottom. --%>
        <li :for={turn <- Enum.reverse(@turns)} class="voice-chat-turn" data-role={turn.role}>
          <span class="voice-chat-who">{if turn.role == "owner", do: "Você", else: "Agente"}</span>
          <p>{turn.text}</p>
        </li>
      </ol>
      <p :if={@thinking} class="voice-chat-thinking" role="status">O agente está pensando…</p>
      <form id="voice-chat-form" phx-submit="voice_turn" class="voice-chat-form">
        <label for="voice-chat-text" class="sr-only">Escrever para o agente</label>
        <input
          id="voice-chat-text"
          name="text"
          maxlength="2000"
          autocomplete="off"
          placeholder="Ou escreva para o agente…"
        />
        <button type="submit">Enviar</button>
      </form>
    </section>
    """
  end
end
