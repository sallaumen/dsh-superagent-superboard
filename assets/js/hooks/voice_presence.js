import {localize, isPortuguese} from "../i18n"

const phaseLabels = {
  permission: ["Microfone", "Cancelar"],
  listening: ["Você", "Enviar agora"],
  transcribing: ["Sua voz", "Cancelar"],
  thinking: ["Agente", "Fechar"],
  generating: ["Agente", "Cancelar"],
  speaking: ["Agente", "Parar a voz"],
  complete: ["Concluído", "Fechar"],
  error: ["Atenção", "Fechar"],
}
let latestVoiceState = null
const activePhases = ["permission", "listening", "transcribing", "thinking", "generating", "speaking"]

export const VoicePresence = {
  mounted() {
    this.phase = "idle"
    this.phaseLabel = this.el.querySelector(".voice-presence-phase")
    this.title = this.el.querySelector(".voice-presence-title")
    this.detail = this.el.querySelector(".voice-presence-detail")
    this.control = this.el.querySelector(".voice-presence-control")
    this.onState = event => {
      latestVoiceState = event.detail
      this.show(event.detail)
    }
    this.onContext = () => {
      if (latestVoiceState && activePhases.includes(latestVoiceState.phase)) this.show(latestVoiceState)
      else if (this.host !== document.querySelector(".board-dialog[open]")) this.hide()
    }
    this.onControl = () => {
      if (["complete", "error", "thinking"].includes(this.phase)) this.hide()
      else window.dispatchEvent(new CustomEvent("board:voice-control", {detail: {phase: this.phase, source: this.source}}))
    }
    // The bars follow the measured input level while listening (CSS reads
    // --voice-level); without measurements they stay at rest.
    this.onLevel = ({detail}) => this.el.style.setProperty("--voice-level", String(detail.level || 0))
    window.addEventListener("board:voice-level", this.onLevel)
    window.addEventListener("board:voice-state", this.onState)
    window.addEventListener("board:voice-context", this.onContext)
    this.control.addEventListener("click", this.onControl)
    this.host = this.el.closest("dialog")
    this.onHostClose = () => this.hide()
    this.host?.addEventListener("close", this.onHostClose)
  },
  show({phase, title, detail, source}) {
    clearTimeout(this.closeTimer)
    if (phase === "idle") return this.hide()
    if (this.host !== document.querySelector(".board-dialog[open]")) return this.hide()
    this.phase = phase
    this.source = source
    this.el.dataset.phase = phase
    this.el.dataset.source = source
    this.phaseLabel.textContent = localize(phaseLabels[phase]?.[0] || "Voz")
    this.control.textContent = source === "browser-dictation" && phase === "listening"
      ? (isPortuguese() ? "Concluir ditado" : "Finish dictation")
      : localize(phaseLabels[phase]?.[1] || "Fechar")
    this.title.textContent = title
    this.detail.textContent = detail
    this.el.hidden = false
    if (phase === "complete") this.closeTimer = setTimeout(() => this.hide(), 5000)
  },
  hide() {
    clearTimeout(this.closeTimer)
    this.phase = "idle"
    this.el.dataset.phase = "idle"
    delete this.el.dataset.source
    this.el.hidden = true
  },
  destroyed() {
    clearTimeout(this.closeTimer)
    window.removeEventListener("board:voice-state", this.onState)
    window.removeEventListener("board:voice-level", this.onLevel)
    window.removeEventListener("board:voice-context", this.onContext)
    this.control.removeEventListener("click", this.onControl)
    this.host?.removeEventListener("close", this.onHostClose)
  },
}
