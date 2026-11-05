import {interruptVoiceOutput, voiceState} from "../voice_state"

// Records only into an editable field. Stopping transcribes; it never sends a
// message or creates a task. The user reviews the result before either action.
export const VoiceRecorder = {
  mounted() {
    this.target = this.el.dataset.target || "#task-title"
    this.question = this.target === "#ask-body"
    this.label = this.el.querySelector("[data-voice-button-label]")
    this.idleLabel = this.el.dataset.label || this.label?.textContent.trim() || "Record by voice"
    this.idleAccessibleLabel = this.el.getAttribute("aria-label") || this.idleLabel
    this.maxSeconds = Number(this.el.dataset.maxSeconds) || 20
    this.recorder = null
    this.stream = null
    this.chunks = []
    this.cancelled = false
    this.destroyedHook = false
    this.onClick = () => this.toggle()
    this.onControl = ({detail}) => {
      if (detail.source !== "recorder") return
      if (detail.phase === "listening") this.stop()
      else this.cancel()
    }
    this.el.addEventListener("click", this.onClick)
    window.addEventListener("board:voice-control", this.onControl)
    this.host = this.el.closest("dialog")
    this.onHostClose = () => {
      if (this.pendingPermission || this.recorder || this.transcribing) this.cancel()
    }
    this.host?.addEventListener("close", this.onHostClose)
  },
  toggle() {
    if (this.recorder?.state === "recording") this.stop()
    else if (!this.pendingPermission && !this.transcribing) this.start()
  },
  async start() {
    if (!document.querySelector(this.target)) {
      voiceState("error", this.question ? "Conversation is closed" : "New task is closed",
        "Open the form before recording.", "recorder")
      return
    }
    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
      voiceState("error", "Recording is unavailable", "Type in the form instead.", "recorder")
      return
    }
    interruptVoiceOutput()
    this.pendingPermission = true
    this.cancelled = false
    voiceState("permission", "Waiting for microphone", "Allow access to start recording.", "recorder")
    try {
      const stream = await navigator.mediaDevices.getUserMedia({audio: true})
      this.pendingPermission = false
      if (this.cancelled || this.destroyedHook) {
        stream.getTracks().forEach(track => track.stop())
        return
      }
      this.stream = stream
      const type = MediaRecorder.isTypeSupported("audio/webm") ? "audio/webm" : ""
      this.recorder = type ? new MediaRecorder(stream, {mimeType: type}) : new MediaRecorder(stream)
      this.chunks = []
      this.recorder.ondataavailable = event => {
        if (event.data.size) this.chunks.push(event.data)
      }
      this.recorder.onstop = () => {
        if (this.cancelled || this.destroyedHook) this.reset()
        else this.finish()
      }
      this.recorder.start()
      this.setButton("Stop & transcribe")
      this.el.dataset.recording = "true"
      voiceState("listening", this.question ? "Listening for a question" : "Listening for a task title",
        `Speak now, then finish. Recording stops after ${this.maxSeconds} seconds.`, "recorder")
      this.timer = setTimeout(() => this.stop(), this.maxSeconds * 1000)
    } catch (_) {
      this.pendingPermission = false
      this.reset()
      if (!this.cancelled) voiceState("error", "Microphone is unavailable", "Check permission or type instead.", "recorder")
    }
  },
  stop() {
    if (!this.recorder || this.recorder.state !== "recording") return
    clearTimeout(this.timer)
    this.timer = null
    this.transcribing = true
    this.el.disabled = true
    voiceState("transcribing", "Transcribing with ElevenLabs", "The result will appear in the form for review.", "recorder")
    this.recorder.stop()
    this.stream?.getTracks().forEach(track => track.stop())
  },
  async finish() {
    const blob = new Blob(this.chunks, {type: this.recorder.mimeType || "audio/webm"})
    if (!blob.size) {
      this.reset()
      voiceState("error", "Nothing was recorded", "Try again or type in the form.", "recorder")
      return
    }
    this.abort = new AbortController()
    try {
      const response = await fetch("/api/voice/transcribe", {
        method: "POST",
        headers: {"content-type": blob.type || "audio/webm"},
        body: blob,
        signal: this.abort.signal,
      })
      const data = await response.json().catch(() => ({}))
      if (this.cancelled || this.destroyedHook) return
      if (!response.ok) {
        this.reset()
        voiceState("error", "Transcription failed", data.error || `HTTP ${response.status}. Try again.`, "recorder")
        return
      }
      const input = document.querySelector(this.target)
      if (!input) {
        this.reset()
        voiceState("error", "The form was closed", "Open it again before recording.", "recorder")
        return
      }
      input.value = data.text
      input.dispatchEvent(new Event("input", {bubbles: true}))
      input.focus()
      this.reset()
      voiceState("complete", this.question ? "Question transcribed" : "Title transcribed",
        this.question ? "Review it before sending." : "Review it before creating the task.", "recorder")
    } catch (error) {
      if (this.cancelled || this.destroyedHook || error?.name === "AbortError") return
      this.reset()
      voiceState("error", "Could not reach the board", "Check the connection and try again.", "recorder")
    }
  },
  cancel() {
    this.cancelled = true
    this.abort?.abort()
    clearTimeout(this.timer)
    this.stream?.getTracks().forEach(track => track.stop())
    if (this.recorder?.state === "recording") this.recorder.stop()
    this.reset()
    voiceState("complete", "Recording cancelled", "Nothing was sent.", "recorder")
  },
  setButton(text) {
    if (this.label) this.label.textContent = text
    this.el.setAttribute("aria-label", text)
  },
  reset() {
    clearTimeout(this.timer)
    this.timer = null
    this.stream?.getTracks().forEach(track => track.stop())
    this.recorder = null
    this.stream = null
    this.chunks = []
    this.abort = null
    this.pendingPermission = false
    this.transcribing = false
    this.el.disabled = false
    if (this.label) this.label.textContent = this.idleLabel
    this.el.setAttribute("aria-label", this.idleAccessibleLabel)
    delete this.el.dataset.recording
  },
  destroyed() {
    const active = this.pendingPermission || this.recorder || this.transcribing
    this.destroyedHook = true
    this.cancelled = true
    this.abort?.abort()
    clearTimeout(this.timer)
    this.stream?.getTracks().forEach(track => track.stop())
    if (this.recorder?.state === "recording") this.recorder.stop()
    this.el.removeEventListener("click", this.onClick)
    window.removeEventListener("board:voice-control", this.onControl)
    this.host?.removeEventListener("close", this.onHostClose)
    if (active && document.querySelector('.voice-presence[data-source="recorder"]:not([hidden])')) {
      voiceState("idle", "", "", "recorder")
    }
  },
}
