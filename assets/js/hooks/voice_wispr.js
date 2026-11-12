import {voiceState} from "../voice_state"

// WisprFlow types what the owner says into the focused field. This hook is
// the binding for that field: the owner selects dictation, holds the Wispr key
// and speaks, and when the dictated text lands (a paste or a burst of
// characters) it is sent once it stops changing. Typing by hand sends on
// Enter instead, so a slow typist is never cut off. Nothing here records
// audio or pays for a transcription.
const settleMs = 700
const idleCloseMs = 30000
const burst = 6

export const VoiceWispr = {
  mounted() {
    this.overlayInput = this.el.querySelector("input")
    this.dictated = false
    this.onOpen = ({detail}) => this.open(Boolean(detail?.followup))
    this.onInput = (event) => this.changed(event)
    // Submitting the Chat form wins over a pending dictation timer.
    this.onSubmit = () => this.close()
    this.onKey = (event) => {
      if (event.isComposing) return
      if (event.key === "Enter") {
        event.preventDefault()
        this.send()
      } else if (event.key === "Escape") {
        event.preventDefault()
        this.close()
      }
    }
    this.onBlur = () => setTimeout(() => {
      if (this.input && document.activeElement !== this.input && !this.input.value.trim()) this.close()
    }, 400)
    window.addEventListener("board:voice-wispr-open", this.onOpen)
    this.onContext = () => {
      if (this.input && this.input !== this.overlayInput && !this.input.closest("dialog")?.open) this.close()
    }
    window.addEventListener("board:voice-context", this.onContext)
  },
  bind(input) {
    this.input = input
    this.input.addEventListener("input", this.onInput)
    this.input.addEventListener("keydown", this.onKey)
    this.input.addEventListener("blur", this.onBlur)
    this.input.form?.addEventListener("submit", this.onSubmit)
  },
  open(followup) {
    this.close()
    // The page behind a native Chat dialog is inert. Dictate directly into
    // its composer while it is open, retaining any draft already typed.
    this.bind(document.querySelector("#panel-voice[open] #voice-chat-text") || this.overlayInput)
    this.dictated = false
    this.lastLength = this.input.value.length
    this.el.dataset.followup = String(followup)
    this.el.hidden = this.input !== this.overlayInput
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
    this.input.value = ""
    this.pushEvent("voice_turn", {text})
    voiceState("thinking", "Pensando…", "O agente está preparando a resposta. Esc cancela.", "wispr")
    this.close()
  },
  close() {
    clearTimeout(this.sendTimer)
    clearTimeout(this.idleTimer)
    if (!this.input) return
    this.input.removeEventListener("input", this.onInput)
    this.input.removeEventListener("keydown", this.onKey)
    this.input.removeEventListener("blur", this.onBlur)
    this.input.form?.removeEventListener("submit", this.onSubmit)
    if (this.input === this.overlayInput) {
      this.input.value = ""
      if (document.activeElement === this.input) this.input.blur()
    }
    this.el.hidden = true
    this.input = null
  },
  destroyed() {
    this.close()
    window.removeEventListener("board:voice-wispr-open", this.onOpen)
    window.removeEventListener("board:voice-context", this.onContext)
  },
}
