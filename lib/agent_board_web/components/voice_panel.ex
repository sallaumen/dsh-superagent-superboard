defmodule AgentBoardWeb.Components.VoicePanel do
  @moduledoc """
  The voice controls of Settings → Voice and summary, split into two columns:
  how the owner talks to the board, and when ElevenLabs talks back.

  Presentation lives here; the events stay the ones `BoardLive` already
  handles (`voice_input`, `voice_replies`,
  `voice_volume`, `voice_speed`, `voice_style`, `voice_pause`,
  `voice_earcons`, `voice_alert_kind`, `voice_browse`,
  `voice_pick`, `voice_preview`, `voice_reset`, `voice_model` and
  `voice_try`). The root with the `VoicePlayer` hook and the `data-volume` /
  `data-lang` attributes lives in the settings pane.
  """

  use Phoenix.Component
  use Gettext, backend: AgentBoardWeb.Gettext

  import AgentBoardWeb.CoreComponents, only: [icon: 1]

  attr :voice, :map, required: true
  attr :repo, :boolean, default: false

  def input_controls(assigns) do
    ~H"""
    <section class="voice-column" aria-labelledby="voice-you-title">
      <h4 id="voice-you-title">{gettext("You speaking")}</h4>
      <p class="voice-column__intro">
        {gettext("How you send messages to the board.")}
      </p>

      <form
        id="voice-input-form"
        phx-change="voice_input"
        phx-auto-recover="ignore"
        class="voice-field"
      >
        <fieldset class="voice-choice-group">
          <legend class="voice-field-label">{gettext("How you send")}</legend>
          <label
            :for={{id, label} <- inputs()}
            class={["voice-choice", @voice.input == id && "is-selected"]}
          >
            <input type="radio" name="input" value={id} checked={@voice.input == id} />
            <span>{label}</span>
          </label>
        </fieldset>
        <p class="voice-note">
          {gettext("Press Space twice to open Chat.")}
        </p>
      </form>

      <div class="voice-field">
        <span class="voice-field-label" id="voice-pause-title">
          {gettext("Silence that ends your speech")}
        </span>
        <div
          class="ab-segmented"
          role="group"
          aria-labelledby="voice-pause-title"
          aria-describedby="voice-pause-hint"
        >
          <button
            :for={{id, label} <- pauses()}
            type="button"
            class={["ab-segment", @voice.pause == id && "is-selected"]}
            aria-pressed={to_string(@voice.pause == id)}
            phx-click="voice_pause"
            phx-value-pause={id}
            disabled={@voice.input != "microphone"}
          >{label}</button>
        </div>
        <p id="voice-pause-hint" class="voice-note">
          {if @voice.input == "microphone",
            do: gettext("Only applies to the board microphone."),
            else: gettext("Only applies to the board microphone. Choose that input to change it.")}
        </p>
      </div>

      <fieldset class="voice-field voice-speak">
        <legend class="voice-field-label">{gettext("Microphone feedback")}</legend>
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

        <p class="voice-note">
          {gettext("Creating and stopping tasks by voice always asks for your confirmation.")}
        </p>
      </fieldset>
    </section>
    """
  end

  def output_controls(assigns) do
    ~H"""
    <section class="voice-column" aria-labelledby="voice-board-title">
      <h4 id="voice-board-title">{gettext("The board speaking")}</h4>
      <p class="voice-column__intro">
        {gettext("ElevenLabs speaks only when you ask, unless you enable specific alerts below.")}
      </p>

      <fieldset class="voice-field voice-scenarios" aria-describedby="voice-scenarios-note">
        <legend class="voice-field-label">{gettext("Automatic alerts")}</legend>
        <p id="voice-scenarios-note" class="voice-note">
          {gettext(
            "Off by default. Progress, queue, sync and daily summaries stay on screen and never speak."
          )}
        </p>
        <div class="voice-scenarios__list">
          <form
            :for={{kind, label} <- alert_kinds()}
            id={"voice-alert-#{kind}"}
            phx-change="voice_alert_kind"
            phx-auto-recover="ignore"
          >
            <input type="hidden" name="kind" value={kind} />
            <input type="hidden" name="enabled" value="false" />
            <label class="voice-toggle">
              <input
                type="checkbox"
                name="enabled"
                value="true"
                checked={String.to_atom(kind) in @voice.alert_kinds}
              />
              <span>{label}</span>
            </label>
          </form>
        </div>
        <p :if={!@voice.configured} class="voice-note">
          {gettext("Add an ElevenLabs key to hear alerts. The board stays silent without it.")}
        </p>
      </fieldset>

      <div :if={@voice.configured} class="voice-field">
        <label for="voice-picker" class="voice-field-label">
          {gettext("ElevenLabs voice")}
          <span class="voice-source-note">
            · {@voice.name || gettext("unnamed")} · <code>{@voice.id}</code>
            · {source_label(@voice.source)}
          </span>
        </label>
        <div class="voice-inline-form">
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
            class="ab-btn"
            phx-click="voice_browse"
            disabled={@voice.loading}
          >
            {cond do
              @voice.loading -> gettext("Loading…")
              @voice.voices in [nil, []] -> gettext("List voices")
              true -> gettext("Refresh list")
            end}
          </button>

          <button type="button" class="ab-btn" phx-click="voice_preview">
            <.icon name="hero-play" class="size-3.5" />{gettext("Listen")}
          </button>

          <button
            :if={@voice.source == :saved}
            type="button"
            class="ab-btn ab-btn--quiet"
            phx-click="voice_reset"
          >
            {gettext("Reset to default")}
          </button>
        </div>
        <p id="voice-picker-note" class="voice-note">{picker_note(@voice.source)}</p>
      </div>

      <div class="voice-field">
        <span class="voice-field-label" id="voice-replies-title">{gettext("Responses")}</span>
        <div class="ab-segmented" role="group" aria-labelledby="voice-replies-title">
          <button
            :for={{id, label} <- replies()}
            type="button"
            class={["ab-segment", @voice.replies == id && "is-selected"]}
            aria-pressed={to_string(@voice.replies == id)}
            phx-click="voice_replies"
            phx-value-replies={id}
          >{label}</button>
        </div>
        <p class="voice-note">
          {if @voice.replies == "short",
            do: gettext("Short: the first sentence is spoken and the rest is written."),
            else: gettext("Full: the whole response is spoken and written.")}
        </p>
      </div>

      <p id="voice-language-note" class="voice-note">
        {gettext(
          "The voice speaks the board language of this browser. Change it in System, Board language."
        )}
      </p>

      <div :if={@voice.configured} class="voice-field">
        <span class="voice-field-label" id="voice-style-title">{gettext("Intonation")}</span>
        <div class="ab-segmented" role="group" aria-labelledby="voice-style-title">
          <button
            :for={{id, label} <- styles()}
            type="button"
            class={["ab-segment", @voice.style == id && "is-selected"]}
            aria-pressed={to_string(@voice.style == id)}
            phx-click="voice_style"
            phx-value-style={id}
          >{label}</button>
        </div>
      </div>

      <div class="voice-field voice-sliders">
        <form id="voice-volume-form" phx-change="voice_volume" phx-auto-recover="ignore">
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

        <form id="voice-speed-form" phx-change="voice_speed" phx-auto-recover="ignore">
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
      </div>

      <div :if={@voice.configured} class="voice-field">
        <label for="voice-model" class="voice-field-label">
          {gettext("Speech model")}
          <span :if={@voice.model_source == :environment} class="voice-source-note">
            {gettext("· set in .env.local")}
          </span>
        </label>
        <form id="voice-model-form" phx-change="voice_model" phx-auto-recover="ignore">
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
              {model.name} — {Gettext.gettext(AgentBoardWeb.Gettext, model.note)}
            </option>
          </select>
        </form>
      </div>

      <form :if={@voice.configured} id="voice-try" phx-submit="voice_try" class="voice-field">
        <label for="voice-phrase" class="voice-field-label">{gettext("Test a phrase")}</label>
        <div class="voice-inline-form">
          <input
            id="voice-phrase"
            name="phrase"
            placeholder={gettext("Type something to hear the agent...")}
            aria-label={gettext("Phrase to speak")}
            class="voice-text-input"
          />
          <button type="submit" class="ab-btn">
            <.icon name="hero-play" class="size-3.5" />{gettext("Play")}
          </button>
        </div>
      </form>

      <p class="voice-note">
        {if @voice.configured,
          do:
            gettext(
              "The ElevenLabs key comes from .env.local. Choose the voice and model here; changes save immediately."
            ),
          else:
            gettext(
              "Without an ElevenLabs key, replies stay written and the board does not speak. Set ELEVENLABS_API_KEY in .env.local and restart the board to enable audio."
            )}
      </p>
    </section>
    """
  end

  defp inputs do
    [
      {"text", gettext("Text, in whichever field is open")},
      {"wispr", gettext("External dictation · Wispr Flow")},
      {"microphone", gettext("Board microphone · ElevenLabs, paid")}
    ]
  end

  defp alert_kinds do
    [
      {"question", gettext("A task asks for your answer")},
      {"blocked", gettext("A task is blocked")},
      {"ready", gettext("A task is ready for review")},
      {"answer", gettext("Yasme answered a task question")}
    ]
  end

  defp replies do
    [{"short", gettext("Short")}, {"full", gettext("Full")}]
  end

  defp styles do
    [
      {"steady", gettext("Stable")},
      {"natural", gettext("Natural")},
      {"expressive", gettext("Expressive")}
    ]
  end

  defp pauses do
    [
      {"short", gettext("Short · 0.8 s")},
      {"normal", gettext("Normal · 1.2 s")},
      {"long", gettext("Long · 1.8 s")}
    ]
  end

  defp speed_label(speed), do: AgentBoardWeb.Numbers.decimal(speed, 2) <> "×"

  defp picker_note(:environment),
    do: gettext("Set in .env.local (ELEVENLABS_VOICE_ID); to change here, remove the variable.")

  defp picker_note(_source),
    do: gettext("This voice speaks your conversations and any alerts you enable.")

  defp source_label(:environment), do: gettext("set in .env.local")
  defp source_label(:saved), do: gettext("chosen here")
  defp source_label(:default), do: gettext("Default voice")
end
