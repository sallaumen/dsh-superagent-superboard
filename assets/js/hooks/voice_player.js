import {voiceInputActive, voiceState} from "../voice_state"

// The server chooses the speech URL. Playback state follows the audio element,
// never the request or the presence of an ElevenLabs key alone.
// The panel root carries the saved volume (0..100); dragging the slider
// applies it at once, before the server has saved it.
const volumeOf = (value) => {
  const n = Number(value)
  return Number.isFinite(n) ? Math.min(Math.max(n, 0), 100) / 100 : 1
}

export const VoicePlayer = {
  mounted() {
    this.audio = new Audio()
    this.audio.volume = volumeOf(this.el.dataset.volume)
    this.onInput = (event) => {
      if (event.target?.name !== "volume") return
      this.audio.volume = volumeOf(event.target.value)
      const readout = this.el.querySelector("[data-voice-volume-readout]")
      if (readout) readout.textContent = `${event.target.value}%`
    }
    this.el.addEventListener("input", this.onInput)
    this.objectUrl = null
    this.generation = 0
    this.onControl = ({detail}) => {
      if (detail.source === "elevenlabs" && this.active) {
        this.cancel()
        voiceState("complete", "Voz interrompida", "A reprodução parou.", "elevenlabs")
      }
    }
    window.addEventListener("board:voice-control", this.onControl)
    this.handleEvent("voice_play", ({url, listen}) => this.play(url, {listen: Boolean(listen)}))
  },
  async play(url, {listen = false} = {}) {
    if (voiceInputActive()) return
    this.cancel()
    const generation = ++this.generation
    this.active = true
    this.abort = new AbortController()
    voiceState("generating", "Preparando a voz do agente", "Esperando o áudio da ElevenLabs.", "elevenlabs")

    let blob
    try {
      const response = await fetch(url, {signal: this.abort.signal})
      if (generation !== this.generation) return
      if (!response.ok) {
        let message = `O pedido de voz falhou (HTTP ${response.status}).`
        try {
          const data = await response.json()
          if (data.error) message = data.error
        } catch (_) {
          // The status still identifies the failed request.
        }
        this.active = false
        voiceState("error", "Não deu para preparar a voz", message, "elevenlabs")
        return
      }
      blob = await response.blob()
      if (generation !== this.generation) return
    } catch (error) {
      if (generation !== this.generation || error?.name === "AbortError") return
      this.active = false
      voiceState("error", "Serviço de voz fora do ar", "Confira a conexão do board e tente de novo.", "elevenlabs")
      return
    }

    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = URL.createObjectURL(blob)
    this.audio.src = this.objectUrl
    this.audio.onplaying = () => {
      if (generation === this.generation) voiceState("speaking", "O agente está falando", "Tocando o áudio da ElevenLabs.", "elevenlabs")
    }
    this.audio.onended = () => {
      if (generation !== this.generation) return
      this.active = false
      voiceState("complete", "O agente terminou de falar", "Reprodução concluída.", "elevenlabs")
      // The reply asked something: hear the answer without a key press.
      if (listen) window.dispatchEvent(new CustomEvent("board:voice-start", {detail: {followup: true}}))
    }
    this.audio.onerror = () => {
      if (generation !== this.generation) return
      this.active = false
      voiceState("error", "O áudio não tocou", "Confira o formato do áudio ou a política do navegador.", "elevenlabs")
    }

    try {
      await this.audio.play()
    } catch (error) {
      if (generation !== this.generation) return
      this.active = false
      voiceState(
        "error",
        "O áudio não tocou",
        error?.name === "NotAllowedError"
          ? "O navegador bloqueou o som. Tente de novo depois de interagir com a página."
          : "Confira o som do navegador e tente de novo.",
        "elevenlabs"
      )
    }
  },
  cancel() {
    this.generation++
    this.active = false
    this.abort?.abort()
    this.abort = null
    if (this.audio) {
      this.audio.onplaying = null
      this.audio.onended = null
      this.audio.onerror = null
      this.audio.pause()
      this.audio.removeAttribute("src")
    }
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = null
  },
  updated() {
    if (this.audio) this.audio.volume = volumeOf(this.el.dataset.volume)
  },
  destroyed() {
    this.el.removeEventListener("input", this.onInput)
    window.removeEventListener("board:voice-control", this.onControl)
    this.cancel()
  },
}
