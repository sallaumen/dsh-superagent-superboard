import {voiceInputActive, voiceState} from "../voice_state"
import {isPortuguese, localize} from "../i18n"

// The server chooses the speech URL. Playback state follows the audio element,
// never the request or the presence of an ElevenLabs key alone.
// The panel root carries the saved volume (0..100); dragging the slider
// applies it at once, before the server has saved it.
const volumeOf = (value) => {
  const n = Number(value)
  return Number.isFinite(n) ? Math.min(Math.max(n, 0), 100) / 100 : 1
}

// How long the owner waited, from the end of their speech to the first word
// of the reply (the VoiceCommand hook marks the end of the speech).
const latencyDetail = () => {
  const endedAt = window.boardVoiceTurnEndedAt
  window.boardVoiceTurnEndedAt = null
  if (!endedAt) return localize("Tocando o áudio da ElevenLabs.")
  const seconds = (performance.now() - endedAt) / 1000
  return seconds < 60
    ? (isPortuguese() ? `Respondi em ${seconds.toFixed(1).replace(".", ",")} s.` : `Responded in ${seconds.toFixed(1)} s.`)
    : localize("Tocando o áudio da ElevenLabs.")
}

export const VoicePlayer = {
  mounted() {
    this.audio = new Audio()
    this.audio.volume = volumeOf(this.el.dataset.volume)
    // Sliders show their value while they move, before the server saves it.
    this.onInput = (event) => {
      const {name, value, id} = event.target || {}
      if (name === "volume") {
        this.audio.volume = volumeOf(value)
        const readout = this.el.querySelector("[data-voice-volume-readout]")
        if (readout) readout.textContent = `${value}%`
      } else if (name === "speed") {
        const readout = this.el.querySelector(`output[for="${id}"]`)
        if (readout) readout.textContent = `${Number(value).toFixed(2).replace(".", ",")}×`
      }
    }
    this.el.addEventListener("input", this.onInput)
    this.generation = 0
    this.onControl = ({detail}) => {
      if (detail.source === "elevenlabs" && this.active) {
        this.cancel()
        voiceState("complete", "Voz interrompida", "A reprodução parou.", "elevenlabs")
      }
    }
    window.addEventListener("board:voice-control", this.onControl)
    this.handleEvent("voice_play", ({url, listen, text}) => this.play(url, {listen: Boolean(listen), text}))
  },
  // The audio element plays the stream as it arrives: the first words are
  // heard about half a second after the request, instead of after the whole
  // file was downloaded.
  play(url, {listen = false, text = ""} = {}) {
    if (voiceInputActive()) return
    this.cancel()
    const generation = ++this.generation
    this.active = true
    voiceState("generating", "Preparando a voz do agente", "Esperando o áudio da ElevenLabs.", "elevenlabs")

    this.audio.onplaying = () => {
      if (generation !== this.generation) return
      // The whole reply is written here; a short reply speaks only its start.
      voiceState("speaking", "O agente está falando", [latencyDetail(), text].filter(Boolean).join(" "), "elevenlabs")
    }
    const finish = () => {
      if (generation !== this.generation || !this.active) return
      clearInterval(this.endWatch)
      this.active = false
      voiceState("complete", "O agente terminou de falar", "Reprodução concluída.", "elevenlabs")
      // The reply asked something: hear the answer without a key press.
      if (listen) window.dispatchEvent(new CustomEvent("board:voice-start", {detail: {followup: true}}))
    }
    this.audio.onended = finish
    // WebKit plays a stream without a length (duration Infinity) to its last
    // word and then freezes, never firing "ended". Playback that stopped
    // advancing for a second without a pause is over.
    let lastTime = -1
    let stillSince = 0
    clearInterval(this.endWatch)
    this.endWatch = setInterval(() => {
      if (generation !== this.generation || this.audio.paused) return
      const now = performance.now()
      if (this.audio.currentTime !== lastTime) {
        lastTime = this.audio.currentTime
        stillSince = now
      } else if (lastTime > 0 && now - stillSince >= 1000) {
        finish()
      }
    }, 250)
    this.audio.onerror = () => {
      if (generation !== this.generation) return
      clearInterval(this.endWatch)
      this.active = false
      // Spent credits, a refused key or a dropped connection: the reply is
      // still heard, in the computer's voice, instead of silence.
      if (text) {
        voiceState("error", "A voz da ElevenLabs falhou",
          "Usando a voz do computador. Confira os créditos e a chave da ElevenLabs.", "elevenlabs")
        window.dispatchEvent(new CustomEvent("phx:speak", {detail: {text, listen, lang: this.el.dataset.lang}}))
        return
      }
      voiceState("error", "A voz não tocou",
        "Confira a chave e o limite da ElevenLabs, ou tente de novo.", "elevenlabs")
    }
    this.audio.src = url
    this.audio.play().catch(error => {
      if (generation !== this.generation || error?.name === "AbortError") return
      clearInterval(this.endWatch)
      this.active = false
      voiceState(
        "error",
        "O áudio não tocou",
        error?.name === "NotAllowedError"
          ? "O navegador bloqueou o som. Tente de novo depois de interagir com a página."
          : "Confira o som do navegador e tente de novo.",
        "elevenlabs"
      )
    })
  },
  cancel() {
    this.generation++
    this.active = false
    if (this.audio) {
      clearInterval(this.endWatch)
      this.audio.onplaying = null
      this.audio.onended = null
      this.audio.onerror = null
      this.audio.pause()
      this.audio.removeAttribute("src")
      // Drops the connection, so an interrupted stream stops downloading.
      this.audio.load()
    }
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
