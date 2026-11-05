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
        <h2>Settings</h2>

        <section :if={@repo} class="settings-shortcuts" aria-labelledby="settings-diagnostics">
          <h3 id="settings-diagnostics">Inspect</h3>
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

        <details id="settings-voice-section" class="settings-fold">
          <summary>
            <span class="settings-fold-label">Voice <small>Speech and feedback</small></span>
            <.icon name="hero-chevron-down" class="settings-fold-chevron size-4" />
          </summary>
          <div class="settings-fold-content">
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
          </div>
        </details>

        <details id="settings-repositories-section" class="settings-fold">
          <summary>
            <span class="settings-fold-label">Repositories <small>Track another repository</small></span>
            <.icon name="hero-chevron-down" class="settings-fold-chevron size-4" />
          </summary>
          <div class="settings-fold-content">
            <form id="track-repo" phx-submit="add" class="settings-track-form">
              <input name="owner" placeholder="owner" aria-label="Owner" />
              <input name="name" placeholder="repo name" aria-label="Repository name" />
              <button type="submit" phx-disable-with="Tracking…">Track repo</button>
            </form>
          </div>
        </details>

        <details id="settings-appearance-section" class="settings-fold">
          <summary>
            <span class="settings-fold-label">Appearance <small>Light and dark themes</small></span>
            <.icon name="hero-chevron-down" class="settings-fold-chevron size-4" />
          </summary>
          <div class="settings-fold-content"><Layouts.theme_toggle /></div>
        </details>

        <details id="settings-system-section" class="settings-fold">
          <summary>
            <span class="settings-fold-label">Version <small>{version_summary(@version)}</small></span>
            <.icon name="hero-chevron-down" class="settings-fold-chevron size-4" />
          </summary>
          <div class="settings-fold-content">
            <SystemPanel.version_panel version={@version} busy={@busy} />
          </div>
        </details>
      </div>
    </details>
    """
  end

  defp version_summary(%{state: :behind}), do: "Update available"
  defp version_summary(%{state: :up_to_date}), do: "Up to date"
  defp version_summary(%{state: :ahead}), do: "Ahead of main"
  defp version_summary(_), do: "Status unknown"
end
