defmodule AgentBoardWeb.BoardComponents.SettingsMenu do
  @moduledoc "Secondary board controls grouped behind a native disclosure."
  use AgentBoardWeb, :live_component

  alias AgentBoardWeb.Components.{SystemPanel, VoicePanel}

  @impl true
  def render(assigns) do
    ~H"""
    <details
      id={@id}
      phx-hook="SettingsMenu"
      class="board-settings"
      data-update-ready={to_string(@version.state == :behind)}
    >
      <summary>
        <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
        <.icon name="hero-chevron-down" class="settings-chevron size-3" />
      </summary>
      <div class="board-settings-body">
        <h2>Board settings</h2>

        <section aria-labelledby="settings-repositories">
          <h3 id="settings-repositories">Repositories</h3>
          <p>Switch repositories above or track another one here.</p>
          <form id="track-repo" phx-submit="add" class="settings-track-form">
            <input name="owner" placeholder="owner" aria-label="Owner" />
            <input name="name" placeholder="repo name" aria-label="Repository name" />
            <button type="submit" phx-disable-with="Tracking…">Track repo</button>
          </form>
        </section>

        <section :if={@repo} aria-labelledby="settings-diagnostics">
          <h3 id="settings-diagnostics">Diagnostics</h3>
          <div class="settings-actions">
            <button
              id="open-activity"
              type="button"
              phx-click="show_panel"
              phx-value-panel="activity"
              data-panel-trigger
              aria-haspopup="dialog"
              aria-controls="panel-activity"
            ><.icon name="hero-clock" class="size-4" />Activity</button>
            <button
              id="open-ai"
              type="button"
              phx-click="show_panel"
              phx-value-panel="ai"
              data-panel-trigger
              aria-haspopup="dialog"
              aria-controls="panel-ai"
            ><.icon name="hero-cpu-chip" class="size-4" />AI calls</button>
          </div>
        </section>

        <section aria-labelledby="settings-voice">
          <h3 id="settings-voice">Voice</h3>
          <p>Pick the agent's ElevenLabs voice and model, then try it.</p>

          <VoicePanel.voice_panel voice={@voice} repo={@repo != nil} />

          <div class="settings-actions">
            <button type="button" phx-click="speak">
              <.icon name="hero-speaker-wave" class="size-4" />Speak status
            </button>
            <button
              :if={@voice.configured and @repo}
              id="voice-dictate"
              type="button"
              phx-hook="VoiceRecorder"
              data-max-seconds="20"
            >
              <.icon name="hero-microphone" class="size-4" />Dictate task
            </button>
            <button :if={not @voice.configured} type="button" phx-click="dictate">
              <.icon name="hero-microphone" class="size-4" />Dictate task
            </button>
          </div>
        </section>

        <section aria-labelledby="settings-appearance">
          <h3 id="settings-appearance">Appearance</h3>
          <Layouts.theme_toggle />
        </section>

        <SystemPanel.version_panel version={@version} busy={@busy} />
      </div>
    </details>
    """
  end
end
