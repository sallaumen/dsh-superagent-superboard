defmodule AgentBoardWeb.BoardComponents.VoiceCommandList do
  @moduledoc """
  "O que posso pedir": every voice command, grouped, from
  `AgentBoard.Voice.Commands` (the same list the spoken help points at).

  An example that needs nothing filled in is a button: it sends the phrase
  as a typed turn (`voice_turn`), so the owner can try a read without
  speaking. Each item says whether it only reads, asks for a yes or acts at
  once. Saying "ajuda" opens this list.
  """
  use Phoenix.Component

  alias AgentBoard.Voice.Commands

  attr :open, :boolean, default: false

  def list(assigns) do
    assigns = assign(assigns, :groups, Commands.groups())

    ~H"""
    <details id="voice-commands" class="voice-commands" open={@open}>
      <summary class="voice-commands-summary">
        O que posso pedir <span class="voice-commands-hint">· ou diga "ajuda"</span>
      </summary>
      <div :for={group <- @groups} class="voice-commands-group">
        <h4 id={"voice-commands-#{group.id}"}>{group.title}</h4>
        <ul aria-labelledby={"voice-commands-#{group.id}"}>
          <li :for={item <- group.items} class="voice-command" data-mode={item.mode}>
            <button
              :if={item.try}
              type="button"
              class="voice-command-say"
              phx-click="voice_turn"
              phx-value-text={item.say}
              title="Enviar esta frase agora"
            >
              “{item.say}”
            </button>
            <span :if={!item.try} class="voice-command-say">“{item.say}”</span>
            <span class="voice-command-does">{item.does}</span>
            <span class="voice-command-mode">{Commands.mode_label(item.mode)}</span>
          </li>
        </ul>
      </div>
    </details>
    """
  end
end
