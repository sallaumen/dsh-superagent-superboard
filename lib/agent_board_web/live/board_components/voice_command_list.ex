defmodule AgentBoardWeb.BoardComponents.VoiceCommandList do
  @moduledoc """
  SuperBoard Skills. Featured reads send a real conversation turn. The
  expandable catalog keeps task-specific examples and their effects explicit.
  """
  use Phoenix.Component
  use Gettext, backend: AgentBoardWeb.Gettext

  import AgentBoardWeb.CoreComponents, only: [icon: 1]

  alias AgentBoard.Voice.Commands

  attr :open, :boolean, default: false
  attr :language, :string, default: "pt-BR"
  attr :featured, :boolean, default: true

  def list(assigns) do
    groups = Commands.groups(assigns.language)

    assigns =
      assign(assigns,
        groups: groups,
        starters: for(group <- groups, item <- group.items, item[:featured], do: item)
      )

    ~H"""
    <section class="sb-skills" aria-label="SuperBoard Skills">
      <h3 :if={@featured}>SuperBoard Skills</h3>
      <div :if={@featured} class="sb-skills__grid">
        <button
          :for={item <- @starters}
          class="sb-skills__card"
          type="button"
          phx-click="voice_turn"
          phx-value-text={item.say}
        >
          <.icon name={skill_icon(item.featured)} class="sb-skills__icon size-5" />
          <span>{item.say}</span>
        </button>
      </div>
      <details id="voice-commands" class="sb-skills__catalog" open={@open}>
        <summary>{if @featured, do: gettext("All skills"), else: "SuperBoard Skills"}</summary>
        <details :for={group <- @groups} class="sb-skills__group">
          <summary>
            <h4>{translated(group.title)}</h4>
          </summary>
          <ul>
            <li :for={item <- group.items} class="sb-skills__item" data-mode={item.mode}>
              <button
                :if={item.try}
                type="button"
                phx-click="voice_turn"
                phx-value-text={item.say}
                title={gettext("Send this phrase now")}
              >{item.say}<.icon name="hero-arrow-up-right" class="size-3" /></button>
              <strong :if={!item.try}>{item.say}</strong>
              <small>{translated(item.does)} · {Commands.mode_label(item.mode)}</small>
            </li>
          </ul>
        </details>
      </details>
    </section>
    """
  end

  defp skill_icon(:overview), do: "hero-squares-2x2"
  defp skill_icon(:changes), do: "hero-calendar-days"
  defp skill_icon(:running), do: "hero-play"
  defp skill_icon(:failures), do: "hero-exclamation-triangle"

  defp translated(msgid), do: Gettext.gettext(AgentBoardWeb.Gettext, msgid)
end
