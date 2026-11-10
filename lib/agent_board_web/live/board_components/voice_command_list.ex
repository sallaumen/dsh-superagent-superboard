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
  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Voice.Commands

  attr :open, :boolean, default: false

  def list(assigns) do
    assigns = assign(assigns, :groups, Commands.groups())

    ~H"""
    <details id="voice-commands" class="voice-commands" open={@open}>
      <summary class="voice-commands-summary">
        {gettext("What can I ask?")}
        <span class="voice-commands-hint">{gettext("· or say \"help\"")}</span>
      </summary>
      <div :for={group <- @groups} class="voice-commands-group">
        <h4 id={"voice-commands-#{group.id}"}>{translated(group.title)}</h4>
        <ul aria-labelledby={"voice-commands-#{group.id}"}>
          <li :for={item <- group.items} class="voice-command" data-mode={item.mode}>
            <button
              :if={item.try}
              type="button"
              class="voice-command-say"
              phx-click="voice_turn"
              phx-value-text={item.say}
              title={gettext("Send this phrase now")}
            >
              “{item.say}”
            </button>
            <span :if={!item.try} class="voice-command-say">“{item.say}”</span>
            <span class="voice-command-does">{translated(item.does)}</span>
            <span class="voice-command-mode">{Commands.mode_label(item.mode)}</span>
          </li>
        </ul>
      </div>
    </details>
    """
  end

  # The list is data (`Commands.groups/0`, English msgids marked for the
  # catalog); what to say stays in the voice's language, the rest follows
  # the interface.
  defp translated(msgid), do: Gettext.gettext(AgentBoardWeb.Gettext, msgid)
end
