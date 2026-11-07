defmodule AgentBoardWeb.BoardComponents.VoicePresence do
  @moduledoc "Browser media activity, presented without changing the board or taking focus."
  use Phoenix.Component

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
      <div class="voice-presence-head">
        <span class="voice-presence-kicker">
          <.icon name="hero-microphone" class="voice-presence-listen-icon size-4" />
          <.icon name="hero-speaker-wave" class="voice-presence-speak-icon size-4" />
          <span class="voice-presence-phase">Voz</span>
        </span>
        <button type="button" class="voice-presence-control">
          Fechar
        </button>
      </div>
      <div class="voice-presence-flow" aria-hidden="true">
        <span
          :for={index <- 0..35}
          class="voice-presence-bar"
          style={"--bar-index: #{index}; --bar-height: #{bar_height(index)}px"}
        />
      </div>
      <div class="voice-presence-copy">
        <h2 id={"#{@id}-title"} class="voice-presence-title">Voz</h2>
        <p class="voice-presence-detail"></p>
      </div>
    </aside>
    """
  end

  defp bar_height(index) do
    envelope = [8, 10, 14, 20, 28, 38, 48, 56, 50, 40, 31, 24, 19, 23, 32, 46, 58, 65]
    Enum.at(envelope, rem(index, length(envelope)))
  end
end
