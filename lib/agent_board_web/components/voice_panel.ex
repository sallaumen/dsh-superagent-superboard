defmodule AgentBoardWeb.Components.VoicePanel do
  @moduledoc """
  The ElevenLabs voice controls of the Voice settings section: which voice
  and model the agent speaks with, the account's voices, a preview, the
  save and a free-form phrase to try the voice.

  Presentation lives here and nowhere else, so a design pass can restyle
  this file without touching `BoardLive` or `SettingsMenu`. The contract is
  the assigns (`voice`, a map with `id`, `source`, `configured`, `voices`,
  `loading`, `pick`, `model`, `model_source`, `models`; and `repo`) and the
  events: `voice_browse`, `voice_pick`, `voice_preview`, `voice_save`,
  `voice_reset`, `voice_model` and `voice_try`.
  """

  use Phoenix.Component

  import AgentBoardWeb.CoreComponents, only: [icon: 1]

  attr :voice, :map, required: true
  attr :repo, :boolean, default: false

  def voice_panel(assigns) do
    ~H"""
    <div id="voice-panel" phx-hook="VoicePlayer" class="voice-panel">
      <p :if={!@voice.configured}>
        no key: set <code class="text-base-content">ELEVENLABS_API_KEY</code>
        in <code class="text-base-content">.env.local</code>
        and restart the board to pick the agent's voice.
      </p>

      <div :if={@voice.configured} class="voice-fields">
        <div class="voice-field">
          <label for="voice-picker" class="voice-field-label">
            Agent voice
            <span class="voice-source-note">
              · <code>{@voice.id}</code> · {source_label(@voice.source)}
            </span>
          </label>
          <div class="settings-actions">
            <select
              id="voice-picker"
              name="voice"
              phx-change="voice_pick"
              aria-label="Agent voice"
              disabled={@voice.source == :environment}
              class="voice-select"
            >
              <option
                :if={is_nil(@voice.voices) or @voice.voices == []}
                value=""
                disabled
                selected={is_nil(@voice.pick)}
              >
                {if @voice.loading, do: "Loading voices…", else: "No voices listed yet"}
              </option>
              <option
                :for={voice <- @voice.voices || []}
                value={voice.id}
                selected={voice.id == @voice.pick}
              >
                {voice.name} · {voice.id}
              </option>
            </select>

            <button
              :if={@voice.source != :environment}
              type="button"
              phx-click="voice_browse"
              disabled={@voice.loading}
            >
              {if @voice.loading, do: "Loading…", else: "List voices"}
            </button>

            <button
              :if={not is_nil(@voice.pick) and @voice.source != :environment}
              type="button"
              phx-click="voice_preview"
            >
              <.icon name="hero-play" class="size-3.5" />Preview
            </button>

            <button
              :if={not is_nil(@voice.pick) and @voice.source != :environment}
              type="button"
              phx-click="voice_save"
              class="voice-save"
            >
              Save
            </button>

            <button
              :if={@voice.source == :saved}
              type="button"
              phx-click="voice_reset"
              class="voice-reset"
            >
              Back to default
            </button>
          </div>
        </div>

        <div class="voice-field">
          <label for="voice-model" class="voice-field-label">
            Speech model
            <span :if={@voice.model_source == :environment} class="voice-source-note">
              · fixed in .env.local
            </span>
          </label>
          <div class="settings-actions">
            <select
              id="voice-model"
              name="model"
              phx-change="voice_model"
              aria-label="TTS model"
              disabled={@voice.model_source == :environment}
              class="voice-select"
            >
              <option
                :for={model <- @voice.models}
                value={model.id}
                selected={model.id == @voice.model}
              >
                {model.name} — {model.note}
              </option>
            </select>
          </div>
        </div>

        <div class="voice-field">
          <label for="voice-announce" class="voice-field-label">Automatic feedback</label>
          <label class="voice-toggle">
            <input
              id="voice-announce"
              type="checkbox"
              name="speak_events"
              phx-change="voice_announce"
              checked={@voice.speak_events}
            /> Speak board events as they happen
          </label>
        </div>

        <form phx-submit="voice_try" class="voice-field">
          <label for="voice-phrase" class="voice-field-label">Try a phrase</label>
          <div class="settings-actions">
            <input
              id="voice-phrase"
              name="phrase"
              placeholder="Type something to hear the agent…"
              aria-label="Phrase to speak"
            />
            <button type="submit"><.icon name="hero-play" class="size-3.5" />Play</button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp source_label(:environment), do: "fixed in .env.local"
  defp source_label(:saved), do: "picked here"
  defp source_label(:default), do: "default voice"
end
