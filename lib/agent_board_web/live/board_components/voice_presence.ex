defmodule AgentBoardWeb.BoardComponents.VoicePresence do
  @moduledoc "Browser media activity, presented without changing the board or taking focus."
  use Phoenix.Component
  use Gettext, backend: AgentBoardWeb.Gettext

  import AgentBoardWeb.CoreComponents, only: [icon: 1]

  attr :id, :string, required: true

  def stage(assigns) do
    ~H"""
    <aside
      id={@id}
      phx-hook="VoicePresence"
      phx-update="ignore"
      hidden
      data-phase="idle"
      class="voice-presence"
      aria-labelledby={"#{@id}-title"}
    >
      <div class="voice-presence-main">
        <span class="voice-presence-symbol" aria-hidden="true">
          <.icon name="hero-microphone" class="voice-presence-listen-icon size-4" />
          <.icon name="hero-speaker-wave" class="voice-presence-speak-icon size-4" />
        </span>
        <div class="voice-presence-copy">
          <span class="voice-presence-phase">{gettext("Voice")}</span>
          <h2 id={"#{@id}-title"} class="voice-presence-title" role="status">{gettext("Voice")}</h2>
          <p class="voice-presence-detail"></p>
        </div>
        <button type="button" class="voice-presence-control">
          {gettext("Close")}
        </button>
      </div>
      <div class="voice-presence-flow" aria-hidden="true">
        <span
          :for={index <- 0..23}
          class="voice-presence-bar"
          style={"--bar-index: #{index}; --bar-height: #{bar_height(index)}px"}
        />
      </div>
    </aside>
    """
  end

  defp bar_height(index) do
    envelope = [4, 6, 9, 13, 18, 24, 20, 14, 8, 5, 7, 12, 19, 23, 17, 10, 6, 4]
    Enum.at(envelope, rem(index, length(envelope)))
  end
end
