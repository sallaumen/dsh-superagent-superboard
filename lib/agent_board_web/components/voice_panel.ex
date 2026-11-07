defmodule AgentBoardWeb.Components.VoicePanel do
  @moduledoc """
  The voice controls of the Voz settings section: the language and the
  volume the agent speaks with, when it speaks (calls for attention and the
  rest of the board), and the ElevenLabs voice and model, a preview, the
  save and a free-form phrase to try the voice.

  Presentation lives here and nowhere else, so a design pass can restyle
  this file without touching `BoardLive` or `SettingsMenu`. The contract is
  the assigns (`voice`, a map with `id`, `source`, `configured`, `voices`,
  `loading`, `pick`, `model`, `model_source`, `models`, `speak_events`,
  `attention`, `language`, `languages`, `volume`; and `repo`) and the
  events: `voice_language`, `voice_volume`, `voice_attention`,
  `voice_announce`, `voice_browse`, `voice_pick`, `voice_preview`,
  `voice_save`, `voice_reset`, `voice_model` and `voice_try`.

  The root carries `data-volume` and `data-lang`: the `VoicePlayer` hook and
  the browser-speech fallback read them, so a change applies to the audio
  already playing.
  """

  use Phoenix.Component

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
        <div class="voice-field">
          <label for="voice-language" class="voice-field-label">Idioma da voz</label>
          <form id="voice-language-form" phx-change="voice_language" class="settings-actions">
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

        <form id="voice-volume-form" phx-change="voice_volume" class="voice-field">
          <label for="voice-volume" class="voice-field-label">
            Volume <output for="voice-volume" data-voice-volume-readout>{@voice.volume}%</output>
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

        <fieldset class="voice-field">
          <legend class="voice-field-label">Quando falar</legend>
          <form id="voice-attention-form" phx-change="voice_attention">
            <input type="hidden" name="attention" value="false" />
            <label class="voice-toggle">
              <input
                id="voice-attention"
                type="checkbox"
                name="attention"
                value="true"
                checked={@voice.attention}
              /> Chamar quando uma tarefa precisar de mim
            </label>
          </form>
          <form :if={@voice.configured} id="voice-announce-form" phx-change="voice_announce">
            <input type="hidden" name="speak_events" value="false" />
            <label class="voice-toggle">
              <input
                id="voice-announce"
                type="checkbox"
                name="speak_events"
                value="true"
                checked={@voice.speak_events}
              /> Narrar o resto: início de tarefa, fila, sincronização e confirmações
            </label>
          </form>
        </fieldset>
      </div>

      <p :if={!@voice.configured} class="voice-note">
        Sem chave, os chamados usam a voz do navegador. Para a voz do agente, defina
        <code class="text-base-content">ELEVENLABS_API_KEY</code>
        no <code class="text-base-content">.env.local</code>
        e reinicie o board.
      </p>

      <div :if={@voice.configured} class="voice-fields">
        <div class="voice-field">
          <label for="voice-picker" class="voice-field-label">
            Voz do agente
            <span class="voice-source-note">
              · <code>{@voice.id}</code> · {source_label(@voice.source)}
            </span>
          </label>
          <div class="settings-actions">
            <form id="voice-picker-form" phx-change="voice_pick" class="voice-inline-form">
              <select
                id="voice-picker"
                name="voice"
                aria-label="Voz do agente"
                disabled={@voice.source == :environment}
                class="voice-select"
              >
                <option
                  :if={is_nil(@voice.voices) or @voice.voices == []}
                  value=""
                  disabled
                  selected={is_nil(@voice.pick)}
                >
                  {if @voice.loading, do: "Carregando vozes…", else: "Nenhuma voz listada ainda"}
                </option>
                <option
                  :for={voice <- @voice.voices || []}
                  value={voice.id}
                  selected={voice.id == @voice.pick}
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
              {if @voice.loading, do: "Carregando…", else: "Listar vozes"}
            </button>

            <button
              :if={not is_nil(@voice.pick) and @voice.source != :environment}
              type="button"
              phx-click="voice_preview"
            >
              <.icon name="hero-play" class="size-3.5" />Ouvir
            </button>

            <button
              :if={not is_nil(@voice.pick) and @voice.source != :environment}
              type="button"
              phx-click="voice_save"
              class="voice-save"
            >
              Salvar
            </button>

            <button
              :if={@voice.source == :saved}
              type="button"
              phx-click="voice_reset"
              class="voice-reset"
            >
              Voltar ao padrão
            </button>
          </div>
        </div>

        <div class="voice-field">
          <label for="voice-model" class="voice-field-label">
            Modelo de fala
            <span :if={@voice.model_source == :environment} class="voice-source-note">
              · definido no .env.local
            </span>
          </label>
          <form id="voice-model-form" phx-change="voice_model" class="settings-actions">
            <select
              id="voice-model"
              name="model"
              aria-label="Modelo de fala"
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
          <label for="voice-phrase" class="voice-field-label">Testar uma frase</label>
          <div class="settings-actions">
            <input
              id="voice-phrase"
              name="phrase"
              placeholder="Digite algo para ouvir o agente…"
              aria-label="Frase para falar"
            />
            <button type="submit"><.icon name="hero-play" class="size-3.5" />Tocar</button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  defp source_label(:environment), do: "definida no .env.local"
  defp source_label(:saved), do: "escolhida aqui"
  defp source_label(:default), do: "voz padrão"
end
