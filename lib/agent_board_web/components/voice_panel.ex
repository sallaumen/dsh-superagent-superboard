defmodule AgentBoardWeb.Components.VoicePanel do
  @moduledoc """
  The ElevenLabs voice controls of the Voice settings section: which voice
  and model the agent speaks with, the account's voices, a preview, the
  save, a spoken board status in the agent's voice and an ElevenLabs
  dictation.

  Presentation lives here and nowhere else, so a design pass can restyle
  this file without touching `BoardLive` or `SettingsMenu`. The contract is
  the assigns (`voice`, `configured`, `voices`, `loading`, `pick`,
  `voice_model`, `voice_models`, `model_source`, `repo`) and the events:
  `voice_browse`, `voice_pick`, `voice_preview`, `voice_save`,
  `voice_reset`, `voice_model` and `voice_speak`. The dictation is pure
  client-side: the `VoiceRecorder` hook records and posts to
  `/api/voice/transcribe`.
  """

  use Phoenix.Component

  import AgentBoardWeb.CoreComponents, only: [icon: 1]

  attr :voice, :map, required: true
  attr :configured, :boolean, required: true
  attr :voices, :list, default: nil
  attr :loading, :boolean, default: false
  attr :pick, :string, default: nil
  attr :voice_model, :string, required: true
  attr :voice_models, :list, default: []
  attr :model_source, :atom, default: :default
  attr :repo, :boolean, default: false

  def voice_panel(assigns) do
    ~H"""
    <div id="voice-panel" phx-hook="VoicePlayer" class="voice-panel">
      <p :if={!@configured}>
        Set <code class="text-base-content">ELEVENLABS_API_KEY</code>
        in <code class="text-base-content">.env.local</code>
        and restart the board to pick the agent's voice.
      </p>

      <div :if={@configured} class="flex flex-col gap-3">
        <div class="settings-actions">
          <span class="voice-current">
            <span class="status-mark bg-success" aria-hidden="true"></span>
            connected · {source_label(@voice.source)}
          </span>

          <select
            name="voice"
            phx-change="voice_pick"
            aria-label="Agent voice"
            disabled={@voice.source == :environment}
            class="voice-select"
          >
            <option :if={is_nil(@voices) or @voices == []} value="" disabled selected={is_nil(@pick)}>
              {if @loading, do: "Loading voices…", else: "No voices listed yet"}
            </option>
            <option :for={voice <- @voices || []} value={voice.id} selected={voice.id == @pick}>
              {voice.name} · {voice.id}
            </option>
          </select>

          <button
            :if={@voice.source != :environment}
            type="button"
            phx-click="voice_browse"
            disabled={@loading}
          >
            {if @loading, do: "Loading…", else: "List voices"}
          </button>

          <button
            :if={not is_nil(@pick) and @voice.source != :environment}
            type="button"
            phx-click="voice_preview"
          >
            Preview
          </button>

          <button
            :if={not is_nil(@pick) and @voice.source != :environment}
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

        <div class="settings-actions">
          <label for="voice-model" class="voice-model-label">
            model <code class="text-base-content">{@voice_model}</code>
          </label>

          <select
            id="voice-model"
            name="model"
            phx-change="voice_model"
            aria-label="TTS model"
            disabled={@model_source == :environment}
            class="voice-select"
          >
            <option :for={model <- @voice_models} value={model.id} selected={model.id == @voice_model}>
              {model.name} — {model.note}
            </option>
          </select>

          <span :if={@model_source == :environment} class="voice-source-note">
            fixed in .env.local
          </span>
        </div>

        <div class="settings-actions">
          <button type="button" phx-click="voice_speak">
            <.icon name="hero-speaker-wave" class="size-4" />Speak status · agent voice
          </button>

          <button
            :if={@repo}
            id="voice-dictate"
            type="button"
            phx-hook="VoiceRecorder"
            data-max-seconds="20"
          >
            <.icon name="hero-microphone" class="size-4" />Dictate task · ElevenLabs
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp source_label(:environment), do: "fixed in .env.local"
  defp source_label(:saved), do: "picked here"
  defp source_label(:default), do: "default voice"
end
