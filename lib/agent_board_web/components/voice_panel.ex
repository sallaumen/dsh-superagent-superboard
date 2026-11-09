defmodule AgentBoardWeb.Components.VoicePanel do
  @moduledoc """
  The voice controls of the Voice settings section: the language and the
  volume the agent speaks with, when it speaks (calls for attention and the
  rest of the board), and the ElevenLabs voice and model, a preview, the
  save and a free-form phrase to try the voice.

  Presentation lives here and nowhere else, so a design pass can restyle
  this file without touching `BoardLive` or `SettingsMenu`. The contract is
  the assigns (`voice`, a map with `id`, `source`, `configured`, `voices`,
  `loading`, `name`, `model`, `model_source`, `models`, `speak_events`,
  `attention`, `language`, `languages`, `volume`, `speed`, `style`,
  `pause`, `earcons`; and `repo`) and the events: `voice_language`,
  `voice_volume`, `voice_speed`, `voice_style`, `voice_pause`,
  `voice_earcons`, `voice_attention`,
  `voice_announce`, `voice_browse`, `voice_pick`, `voice_preview`,
  `voice_reset`, `voice_model` and `voice_try`.

  Every form here mirrors a saved setting, so it opts out of LiveView's form
  recovery (`phx-auto-recover="ignore"`): on a reconnect, recovery re-sent
  the voice picker without a value, which crashed the board, and replayed
  the language confirmation out loud.

  The root carries `data-volume` and `data-lang`: the `VoicePlayer` hook and
  the browser-speech fallback read them, so a change applies to the audio
  already playing.
  """

  use Phoenix.Component
  use Gettext, backend: AgentBoardWeb.Gettext

  import AgentBoardWeb.CoreComponents, only: [icon: 1]

  attr :voice, :map, required: true
  attr :repo, :boolean, default: false

  def voice_panel(assigns) do
    ~H"""
    <div
      id="voice-panel"
      phx-hook="VoicePlayer"
      class="voice-panel"
      data-volume={@voice.volume}
      data-lang={@voice.language}
    >
      <div class="voice-fields">
        <form
          id="voice-input-form"
          phx-change="voice_input"
          phx-auto-recover="ignore"
          class="voice-field"
        >
          <label for="voice-input" class="voice-field-label">
            {gettext("Your voice to the agent")}
            <span class="voice-source-note">{gettext("· press Space twice to start input")}</span>
          </label>
          <div class="settings-actions">
            <select id="voice-input" name="input" class="voice-select">
              <option :for={{id, name} <- inputs()} value={id} selected={id == @voice.input}>
                {name}
              </option>
            </select>
          </div>
        </form>

        <form
          id="voice-engine-form"
          phx-change="voice_engine"
          phx-auto-recover="ignore"
          class="voice-field"
        >
          <label for="voice-engine" class="voice-field-label">
            {gettext("Voice engine")}
            <span :if={!@voice.configured} class="voice-source-note">
              {gettext("· without an ElevenLabs key, always use the browser voice")}
            </span>
          </label>
          <div class="settings-actions">
            <select id="voice-engine" name="engine" class="voice-select">
              <option :for={{id, name} <- engines()} value={id} selected={id == @voice.engine}>
                {name}
              </option>
            </select>
          </div>
        </form>

        <form
          id="voice-replies-form"
          phx-change="voice_replies"
          phx-auto-recover="ignore"
          class="voice-field"
        >
          <label for="voice-replies" class="voice-field-label">{gettext("Spoken Responses")}</label>
          <div class="settings-actions">
            <select id="voice-replies" name="replies" class="voice-select">
              <option :for={{id, name} <- replies()} value={id} selected={id == @voice.replies}>
                {name}
              </option>
            </select>
          </div>
        </form>

        <div class="voice-field">
          <label for="voice-language" class="voice-field-label">{gettext("Voice language")}</label>
          <form
            id="voice-language-form"
            phx-change="voice_language"
            phx-auto-recover="ignore"
            class="settings-actions"
          >
            <select id="voice-language" name="language" class="voice-select">
              <option
                :for={lang <- @voice.languages}
                value={lang.id}
                selected={lang.id == @voice.language}
              >
                {lang.name}
              </option>
            </select>
          </form>
        </div>

        <form
          id="voice-volume-form"
          phx-change="voice_volume"
          phx-auto-recover="ignore"
          class="voice-field"
        >
          <label for="voice-volume" class="voice-field-label">
            {gettext("Volume")}
            <output for="voice-volume" data-voice-volume-readout>{@voice.volume}%</output>
          </label>
          <input
            id="voice-volume"
            type="range"
            name="volume"
            min="0"
            max="100"
            step="5"
            value={@voice.volume}
            phx-debounce="250"
            aria-valuetext={"#{@voice.volume}%"}
            class="voice-volume"
          />
        </form>

        <form
          id="voice-speed-form"
          phx-change="voice_speed"
          phx-auto-recover="ignore"
          class="voice-field"
        >
          <label for="voice-speed" class="voice-field-label">
            {gettext("Speed")} <output for="voice-speed">{speed_label(@voice.speed)}</output>
          </label>
          <input
            id="voice-speed"
            type="range"
            name="speed"
            min="0.8"
            max="1.2"
            step="0.05"
            value={@voice.speed}
            phx-debounce="250"
            aria-valuetext={speed_label(@voice.speed)}
            class="voice-volume"
          />
        </form>

        <form
          :if={@voice.configured}
          id="voice-style-form"
          phx-change="voice_style"
          phx-auto-recover="ignore"
          class="voice-field"
        >
          <label for="voice-style" class="voice-field-label">{gettext("Intonation")}</label>
          <div class="settings-actions">
            <select id="voice-style" name="style" class="voice-select">
              <option
                :for={{id, name} <- styles()}
                value={id}
                selected={id == @voice.style}
              >
                {name}
              </option>
            </select>
          </div>
        </form>

        <form
          id="voice-pause-form"
          phx-change="voice_pause"
          phx-auto-recover="ignore"
          class="voice-field"
        >
          <label for="voice-pause" class="voice-field-label">
            {gettext("Pause before sending")}
            <span class="voice-source-note">{gettext("· how much silence ends your speech")}</span>
          </label>
          <div class="settings-actions">
            <select id="voice-pause" name="pause" class="voice-select">
              <option
                :for={{id, name} <- pauses()}
                value={id}
                selected={id == @voice.pause}
              >
                {name}
              </option>
            </select>
          </div>
        </form>

        <fieldset class="voice-field">
          <legend class="voice-field-label">{gettext("When to speak")}</legend>
          <form id="voice-attention-form" phx-change="voice_attention" phx-auto-recover="ignore">
            <input type="hidden" name="attention" value="false" />
            <label class="voice-toggle">
              <input
                id="voice-attention"
                type="checkbox"
                name="attention"
                value="true"
                checked={@voice.attention}
              /> {gettext("Notify me when a task needs me")}
            </label>
          </form>
          <form
            id="voice-announce-form"
            phx-change="voice_announce"
            phx-auto-recover="ignore"
          >
            <input type="hidden" name="speak_events" value="false" />
            <label class="voice-toggle">
              <input
                id="voice-announce"
                type="checkbox"
                name="speak_events"
                value="true"
                checked={@voice.speak_events}
              /> {gettext("Narrate the rest: task start, queue, synchronization, and confirmations")}
            </label>
          </form>
          <form id="voice-earcons-form" phx-change="voice_earcons" phx-auto-recover="ignore">
            <input type="hidden" name="earcons" value="false" />
            <label class="voice-toggle">
              <input
                id="voice-earcons"
                type="checkbox"
                name="earcons"
                value="true"
                checked={@voice.earcons}
              /> {gettext("Short sound when opening and closing the microphone")}
            </label>
          </form>
        </fieldset>
      </div>

      <p :if={!@voice.configured} class="voice-note">
        {gettext(
          "Without a key, the agent speaks with the browser's voice (free). For ElevenLabs' voice, set"
        )}
        <code class="text-base-content">ELEVENLABS_API_KEY</code>
        {gettext("in")} <code class="text-base-content">.env.local</code>
        {gettext("and restart the board.")}
      </p>

      <div :if={@voice.configured} class="voice-fields">
        <div class="voice-field">
          <label for="voice-picker" class="voice-field-label">
            {gettext("ElevenLabs voice")}
            <span class="voice-source-note">
              · {@voice.name || gettext("unnamed")} · <code>{@voice.id}</code>
              · {source_label(@voice.source)}
            </span>
          </label>
          <div class="settings-actions">
            <form
              id="voice-picker-form"
              phx-change="voice_pick"
              phx-auto-recover="ignore"
              class="voice-inline-form"
            >
              <select
                id="voice-picker"
                name="voice"
                aria-label={gettext("ElevenLabs Voice")}
                aria-describedby="voice-picker-note"
                disabled={@voice.source == :environment}
                class="voice-select"
              >
                <%!-- Before "List voices" the picker still names the voice in
                     use: a blank picker read as "nothing was saved". --%>
                <option
                  :if={not Enum.any?(@voice.voices || [], &(&1.id == @voice.id))}
                  value={@voice.id}
                  selected
                >
                  {@voice.name || gettext("Current voice")} · {@voice.id}
                </option>
                <option
                  :for={voice <- @voice.voices || []}
                  value={voice.id}
                  selected={voice.id == @voice.id}
                >
                  {voice.name} · {voice.id}
                </option>
              </select>
            </form>

            <button
              :if={@voice.source != :environment}
              type="button"
              phx-click="voice_browse"
              disabled={@voice.loading}
            >
              {cond do
                @voice.loading -> gettext("Loading…")
                @voice.voices in [nil, []] -> gettext("List voices")
                true -> gettext("Refresh list")
              end}
            </button>

            <button type="button" phx-click="voice_preview">
              <.icon name="hero-play" class="size-3.5" />{gettext("Listen")}
            </button>

            <button
              :if={@voice.source == :saved}
              type="button"
              phx-click="voice_reset"
              class="voice-reset"
            >
              {gettext("Reset to default")}
            </button>
          </div>
          <p id="voice-picker-note" class="voice-source-note">
            {picker_note(@voice.engine, @voice.source)}
          </p>
        </div>

        <div class="voice-field">
          <label for="voice-model" class="voice-field-label">
            {gettext("Speech model")}
            <span :if={@voice.model_source == :environment} class="voice-source-note">
              {gettext("· set in .env.local")}
            </span>
          </label>
          <form
            id="voice-model-form"
            phx-change="voice_model"
            phx-auto-recover="ignore"
            class="settings-actions"
          >
            <select
              id="voice-model"
              name="model"
              aria-label={gettext("Speech model")}
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
          </form>
        </div>

        <form id="voice-try" phx-submit="voice_try" class="voice-field">
          <label for="voice-phrase" class="voice-field-label">{gettext("Test a phrase")}</label>
          <div class="settings-actions">
            <input
              id="voice-phrase"
              name="phrase"
              placeholder={gettext("Type something to hear the agent...")}
              aria-label={gettext("Phrase to speak")}
            />
            <button type="submit"><.icon name="hero-play" class="size-3.5" />{gettext("Play")}</button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp speed_label(speed),
    do:
      :erlang.float_to_binary(speed * 1.0, decimals: 2)
      |> String.replace(".", ",")
      |> Kernel.<>("×")

  defp inputs,
    do: [
      {"wispr", gettext("WisprFlow (types into the board, free)")},
      {"microphone", gettext("Board microphone (ElevenLabs transcription, paid)")}
    ]

  defp engines,
    do: [
      {"browser", gettext("Browser for everything (free)")},
      {"mixed", gettext("Mixed: ElevenLabs only for alerts")},
      {"elevenlabs", gettext("ElevenLabs for everything (paid)")}
    ]

  defp replies,
    do: [
      {"short", gettext("Short: speak the first sentence, write the rest")},
      {"full", gettext("Full responses")}
    ]

  defp styles,
    do: [
      {"steady", gettext("Stable")},
      {"natural", gettext("Natural")},
      {"expressive", gettext("Expressive")}
    ]

  defp pauses,
    do: [
      {"short", gettext("Short · 0.8 s")},
      {"normal", gettext("Normal · 1.2 s")},
      {"long", gettext("Long · 1.8 s")}
    ]

  # Explain what the picked voice does under each engine.
  defp picker_note(_engine, :environment),
    do: gettext("Set in .env.local (ELEVENLABS_VOICE_ID); to change here, remove the variable.")

  defp picker_note("elevenlabs", _source),
    do: gettext("Choose from the saved list. This voice speaks everything.")

  defp picker_note("mixed", _source),
    do:
      gettext(
        "Choose from the saved list. With Mixed mode, this voice speaks alerts and code-agent replies; conversation uses the browser voice."
      )

  defp picker_note(_engine, _source),
    do:
      gettext(
        "Choose from the saved list. Browser mode does not use this voice; choose Mixed or ElevenLabs for everything in Voice engine."
      )

  defp source_label(:environment), do: gettext("set in .env.local")
  defp source_label(:saved), do: gettext("chosen here")
  defp source_label(:default), do: gettext("Default voice")
end
