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
  `attention`, `language`, `languages`, `volume`, `speed`, `style`,
  `pause`, `earcons`; and `repo`) and the events: `voice_language`,
  `voice_volume`, `voice_speed`, `voice_style`, `voice_pause`,
  `voice_earcons`, `voice_attention`,
  `voice_announce`, `voice_browse`, `voice_pick`, `voice_preview`,
  `voice_save`, `voice_reset`, `voice_model` and `voice_try`.

  Every form here mirrors a saved setting, so it opts out of LiveView's form
  recovery (`phx-auto-recover="ignore"`): on a reconnect, recovery re-sent
  the voice picker without a value, which crashed the board, and replayed
  the language confirmation out loud.

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
        <form
          id="voice-input-form"
          phx-change="voice_input"
          phx-auto-recover="ignore"
          class="voice-field"
        >
          <label for="voice-input" class="voice-field-label">
            Sua voz para o agente
            <span class="voice-source-note">· espaço duas vezes abre a entrada</span>
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
            Voz do agente
            <span :if={!@voice.configured} class="voice-source-note">
              · sem chave ElevenLabs, sempre a do navegador
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
          <label for="voice-replies" class="voice-field-label">Respostas faladas</label>
          <div class="settings-actions">
            <select id="voice-replies" name="replies" class="voice-select">
              <option :for={{id, name} <- replies()} value={id} selected={id == @voice.replies}>
                {name}
              </option>
            </select>
          </div>
        </form>

        <div class="voice-field">
          <label for="voice-language" class="voice-field-label">Idioma da voz</label>
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

        <form
          id="voice-speed-form"
          phx-change="voice_speed"
          phx-auto-recover="ignore"
          class="voice-field"
        >
          <label for="voice-speed" class="voice-field-label">
            Velocidade <output for="voice-speed">{speed_label(@voice.speed)}</output>
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
          <label for="voice-style" class="voice-field-label">Entonação</label>
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
            Pausa para enviar
            <span class="voice-source-note">· quanto silêncio encerra a sua fala</span>
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
          <legend class="voice-field-label">Quando falar</legend>
          <form id="voice-attention-form" phx-change="voice_attention" phx-auto-recover="ignore">
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
              /> Narrar o resto: início de tarefa, fila, sincronização e confirmações
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
              /> Som curto ao abrir e fechar o microfone
            </label>
          </form>
        </fieldset>
      </div>

      <p :if={!@voice.configured} class="voice-note">
        Sem chave, o agente fala com a voz do navegador (grátis). Para a voz da ElevenLabs, defina
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
            <form
              id="voice-picker-form"
              phx-change="voice_pick"
              phx-auto-recover="ignore"
              class="voice-inline-form"
            >
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
          <form
            id="voice-model-form"
            phx-change="voice_model"
            phx-auto-recover="ignore"
            class="settings-actions"
          >
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

  defp speed_label(speed),
    do:
      :erlang.float_to_binary(speed * 1.0, decimals: 2)
      |> String.replace(".", ",")
      |> Kernel.<>("×")

  defp inputs,
    do: [
      {"wispr", "WisprFlow (digita no board, sem custo)"},
      {"microphone", "Microfone do board (transcrição ElevenLabs, paga)"}
    ]

  defp engines,
    do: [
      {"browser", "Navegador (grátis)"},
      {"mixed", "Misto: ElevenLabs só nos chamados"},
      {"elevenlabs", "ElevenLabs em tudo (pago)"}
    ]

  defp replies,
    do: [
      {"short", "Curtas: falo a primeira frase, o resto fica escrito"},
      {"full", "Completas"}
    ]

  defp styles,
    do: [{"steady", "Estável"}, {"natural", "Natural"}, {"expressive", "Expressiva"}]

  defp pauses,
    do: [{"short", "Curta · 0,8 s"}, {"normal", "Normal · 1,2 s"}, {"long", "Longa · 1,8 s"}]

  defp source_label(:environment), do: "definida no .env.local"
  defp source_label(:saved), do: "escolhida aqui"
  defp source_label(:default), do: "voz padrão"
end
