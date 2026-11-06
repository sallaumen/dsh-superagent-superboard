import {interruptVoiceOutput, voiceState} from "../voice_state"

const doubleSpaceMs = 420
const maxSeconds = 20
const source = "command-recorder"

const stopTracks = stream => stream?.getTracks().forEach(track => track.stop())

// Capture belongs to the board, never to a task form. The only start path is
// the second trusted Space keypress while the board has neutral focus.
export const VoiceCommand = {
  mounted() {
    this.phase = "idle"
    this.generation = 0
    this.firstSpaceAt = 0
    this.stream = null
    this.recorder = null
    this.chunks = []
    this.onKeyDown = event => this.handleKeyDown(event)
    this.onDialogCancel = event => {
      if (!this.suppressDialogCancel || !event.target.matches(".board-dialog")) return
      event.preventDefault()
      event.stopImmediatePropagation()
      this.suppressDialogCancel = false
    }
    // A pointer action takes precedence over a deferred page scroll; moving
    // the page on pointerdown could change the control that receives the click.
    this.onPointerDown = () => this.clearFirstSpace()
    this.onVisibility = () => {
      if (document.hidden) this.cancel()
    }
    this.onPageHide = () => this.cancel()
    // The permission prompt can blur the window; only an active recording
    // is cancelled on blur. visibilitychange still cancels either phase.
    this.onBlur = () => {
      if (this.phase === "listening") this.cancel()
    }
    this.onContext = () => {
      if (this.phase === "idle") return
      const board = document.querySelector("#board-page")
      const dialog = document.querySelector(".board-dialog[open]")?.id || null
      if (dialog !== this.originDialog || board?.dataset.baseUrl !== this.repoPath ||
        location.pathname + location.search !== this.originUrl) {
        this.cancel()
      }
    }
    this.onControl = ({detail}) => {
      if (detail.source !== source) return
      if (this.phase === "listening") this.stop()
      else this.cancel()
    }
    this.onStartRequest = () => {
      if (this.phase === "idle") this.start()
    }
    this.onStopRequest = () => {
      if (this.phase === "listening") this.stop()
      else if (this.phase !== "idle") this.cancel()
    }
    document.addEventListener("keydown", this.onKeyDown, true)
    document.addEventListener("cancel", this.onDialogCancel, true)
    document.addEventListener("pointerdown", this.onPointerDown)
    document.addEventListener("visibilitychange", this.onVisibility)
    window.addEventListener("pagehide", this.onPageHide)
    window.addEventListener("blur", this.onBlur)
    window.addEventListener("board:voice-context", this.onContext)
    window.addEventListener("board:voice-control", this.onControl)
    window.addEventListener("board:voice-start", this.onStartRequest)
    window.addEventListener("board:voice-stop", this.onStopRequest)
  },
  handleKeyDown(event) {
    if (event.key === "Escape") {
      this.clearFirstSpace(true)
      if (this.phase !== "idle") {
        event.preventDefault()
        event.stopImmediatePropagation()
        // Native dialogs can emit cancel after keydown; keep this Escape for
        // the microphone so the task conversation stays open.
        this.suppressDialogCancel = true
        setTimeout(() => { this.suppressDialogCancel = false }, 100)
        this.cancel()
      }
      return
    }
    if (event.code !== "Space" || event.key !== " " || event.repeat || event.isComposing ||
      event.ctrlKey || event.altKey || event.metaKey || event.shiftKey || !event.isTrusted ||
      event.defaultPrevented || document.hidden || !document.hasFocus()) {
      this.clearFirstSpace(true)
      return
    }

    const focus = document.activeElement
    const dialog = document.querySelector(".board-dialog[open]")
    const neutralFocus = focus === document.body || focus === document.documentElement || focus === this.el
    const conversationHeading = dialog?.id === "panel-conversation" && focus?.id === "panel-title-conversation"
    if (!neutralFocus && !conversationHeading) {
      this.clearFirstSpace(true)
      return
    }
    if ((dialog && dialog.id !== "panel-conversation") || document.querySelector("[data-board-menu][open]")) {
      this.clearFirstSpace(true)
      return
    }

    event.preventDefault()
    const now = performance.now()
    if (this.firstSpaceAt && now - this.firstSpaceAt <= doubleSpaceMs) {
      this.clearFirstSpace()
      if (this.phase === "idle") this.start()
      else if (this.phase === "listening") this.stop()
      else this.cancel()
      return
    }

    this.clearFirstSpace(true)
    this.firstSpaceAt = now
    // Native Space scroll is delayed briefly so a double press never jumps.
    // With neutral focus, the document is the browser's scroll target.
    this.scrollTimer = setTimeout(() => this.clearFirstSpace(true), doubleSpaceMs)
  },
  clearFirstSpace(replayScroll = false) {
    const pending = Boolean(this.firstSpaceAt)
    clearTimeout(this.scrollTimer)
    this.scrollTimer = null
    this.firstSpaceAt = 0
    if (replayScroll && pending) {
      window.scrollBy({top: Math.round(window.innerHeight * 0.9), behavior: "auto"})
    }
  },
  async start() {
    if (this.el.dataset.configured !== "true") {
      voiceState("error", "Voice transcription is unavailable", "Type a request instead.", source)
      return
    }
    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
      voiceState("error", "Recording is unavailable", "Type a request instead.", source)
      return
    }
    const generation = ++this.generation
    this.phase = "permission"
    this.repoPath = document.querySelector("#board-page")?.dataset.baseUrl
    this.originDialog = document.querySelector(".board-dialog[open]")?.id || null
    this.originUrl = location.pathname + location.search
    interruptVoiceOutput()
    voiceState("permission", "Waiting for microphone", "Allow access to record one command.", source)
    try {
      const stream = await navigator.mediaDevices.getUserMedia({audio: true})
      if (generation !== this.generation) {
        stopTracks(stream)
        return
      }
      if (document.hidden || !document.hasFocus() || !this.el.isConnected) {
        stopTracks(stream)
        this.reset()
        voiceState("complete", "Recording cancelled", "The board is no longer in focus.", source)
        return
      }
      this.stream = stream
      for (const track of stream.getTracks()) {
        track.addEventListener("ended", () => {
          if (this.phase === "listening") this.cancel("Microphone disconnected")
        })
      }
      const type = MediaRecorder.isTypeSupported("audio/webm") ? "audio/webm" : ""
      const recorder = type ? new MediaRecorder(stream, {mimeType: type}) : new MediaRecorder(stream)
      this.recorder = recorder
      this.chunks = []
      recorder.ondataavailable = event => {
        if (event.data.size) this.chunks.push(event.data)
      }
      recorder.onstop = () => {
        if (generation === this.generation && this.phase === "transcribing") this.finish(generation)
      }
      recorder.onerror = () => {
        this.cancel()
        voiceState("error", "Microphone recording failed", "Type a request instead.", source)
      }
      recorder.start()
      this.phase = "listening"
      voiceState("listening", "Listening for a command",
        `Press Space twice to finish, or Escape to cancel. Stops after ${maxSeconds} seconds.`, source)
      this.recordTimer = setTimeout(() => this.stop(), maxSeconds * 1000)
    } catch (_) {
      if (generation !== this.generation) return
      this.reset()
      voiceState("error", "Microphone is unavailable", "Check permission or type instead.", source)
    }
  },
  stop() {
    if (this.phase !== "listening" || this.recorder?.state !== "recording") return
    clearTimeout(this.recordTimer)
    this.phase = "transcribing"
    voiceState("transcribing", "Transcribing command", "The microphone is off while audio is processed.", source)
    try {
      this.recorder.stop()
    } catch (_) {
      this.cancel()
      voiceState("error", "Microphone recording failed", "Type a request instead.", source)
    } finally {
      stopTracks(this.stream)
      this.stream = null
    }
  },
  async finish(generation) {
    const blob = new Blob(this.chunks, {type: this.recorder?.mimeType || "audio/webm"})
    if (!blob.size) {
      this.reset()
      voiceState("error", "Nothing was recorded", "Press Space twice to try again.", source)
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
      if (generation !== this.generation) return
      if (!response.ok) {
        this.reset()
        voiceState("error", "Transcription failed", data.error || `HTTP ${response.status}`, source)
        return
      }
      const transcript = typeof data.text === "string" ? data.text.trim() : ""
      if (!transcript) {
        this.reset()
        voiceState("error", "No words recognized", "Press Space twice to try again.", source)
        return
      }
      this.reset()
      voiceState("complete", "Command transcribed", "Review the words before taking action.", source)
      window.dispatchEvent(new Event("board:panel-intent"))
      this.pushEvent("voice_transcript", {text: transcript})
    } catch (error) {
      if (generation !== this.generation || error?.name === "AbortError") return
      this.reset()
      voiceState("error", "Could not reach the board", "Check the connection and try again.", source)
    }
  },
  cancel(reason = "Recording cancelled") {
    this.clearFirstSpace()
    if (this.phase === "idle") return
    ++this.generation
    this.abort?.abort()
    this.reset()
    voiceState("complete", reason, "Nothing was sent.", source)
  },
  reset() {
    clearTimeout(this.recordTimer)
    stopTracks(this.stream)
    if (this.recorder?.state === "recording") {
      try { this.recorder.stop() } catch (_) { /* The stream is already released. */ }
    }
    this.phase = "idle"
    this.originDialog = null
    this.originUrl = null
    this.stream = null
    this.recorder = null
    this.chunks = []
    this.abort = null
  },
  disconnected() { this.cancel() },
  destroyed() {
    this.cancel()
    document.removeEventListener("keydown", this.onKeyDown, true)
    document.removeEventListener("cancel", this.onDialogCancel, true)
    document.removeEventListener("pointerdown", this.onPointerDown)
    document.removeEventListener("visibilitychange", this.onVisibility)
    window.removeEventListener("pagehide", this.onPageHide)
    window.removeEventListener("blur", this.onBlur)
    window.removeEventListener("board:voice-context", this.onContext)
    window.removeEventListener("board:voice-control", this.onControl)
    window.removeEventListener("board:voice-start", this.onStartRequest)
    window.removeEventListener("board:voice-stop", this.onStopRequest)
  },
}
