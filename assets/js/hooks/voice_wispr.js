import {voiceState} from "../voice_state"

// WisprFlow types what the owner says into the focused field. This hook is
// that field: double Space opens it focused, the owner holds the Wispr key
// and speaks, and when the dictated text lands (a paste or a burst of
// characters) it is sent once it stops changing. Typing by hand sends on
// Enter instead, so a slow typist is never cut off. Nothing here records
// audio or pays for a transcription.
const settleMs = 700
const idleCloseMs = 30000
const burst = 6

export const VoiceWispr = {
  mounted() {
    this.input = this.el.querySelector("input")
    this.dictated = false
    this.onOpen = ({detail}) => this.open(Boolean(detail?.followup))
    this.onInput = (event) => this.changed(event)
    this.onKey = (event) => {
      if (event.key === "Enter") {
        event.preventDefault()
        this.send()
      } else if (event.key === "Escape") {
        event.preventDefault()
        this.close()
      }
    }
    this.onBlur = () => setTimeout(() => {
      if (document.activeElement !== this.input && !this.input.value.trim()) this.close()
    }, 400)
    window.addEventListener("board:voice-wispr-open", this.onOpen)
    this.input.addEventListener("input", this.onInput)
    this.input.addEventListener("keydown", this.onKey)
    this.input.addEventListener("blur", this.onBlur)
  },
  open(followup) {
    clearTimeout(this.sendTimer)
    clearTimeout(this.idleTimer)
    this.dictated = false
    this.lastLength = 0
    this.input.value = ""
    this.el.dataset.followup = String(followup)
    this.el.hidden = false
    this.input.focus()
    voiceState("idle", "", "", "wispr")
    this.idleTimer = setTimeout(() => {
      if (!this.input.value.trim()) this.close()
    }, idleCloseMs)
  },
  changed(event) {
    const length = this.input.value.length
    const pasted = (event.inputType || "").startsWith("insertFromPaste")
    const chunk = (event.data || "").length >= burst || length - (this.lastLength || 0) >= burst
    this.lastLength = length
    if (pasted || chunk) this.dictated = true
    clearTimeout(this.sendTimer)
    if (this.dictated) this.sendTimer = setTimeout(() => this.send(), settleMs)
  },
  send() {
    clearTimeout(this.sendTimer)
    const text = this.input.value.trim()
    if (!text) return
    window.boardVoiceTurnEndedAt = performance.now()
    this.pushEvent("voice_turn", {text})
    voiceState("thinking", "Pensando…", "O agente está preparando a resposta. Esc cancela.", "wispr")
    this.close()
  },
  close() {
    clearTimeout(this.sendTimer)
    clearTimeout(this.idleTimer)
    this.input.value = ""
    this.el.hidden = true
    if (document.activeElement === this.input) this.input.blur()
  },
  destroyed() {
    this.close()
    window.removeEventListener("board:voice-wispr-open", this.onOpen)
  },
}
