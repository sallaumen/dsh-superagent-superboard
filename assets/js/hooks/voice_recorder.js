// Records the microphone and transcribes with the board's /api/voice/transcribe
// (ElevenLabs Scribe). The transcript fills the create-task title, like the
// browser dictation does. First click records, second click stops and uploads;
// the recording also stops by itself after data-max-seconds.
export const VoiceRecorder = {
  mounted() {
    // The input the transcript lands in: the task title by default, the
    // ask input when data-target names it.
    this.target = this.el.dataset.target || "#task-title"
    this.idleLabel = this.el.dataset.label || this.el.textContent.trim()
    this.maxSeconds = Number(this.el.dataset.maxSeconds) || 20
    this.recorder = null
    this.stream = null
    this.chunks = []
    this.timer = null
    this.el.addEventListener("click", () => this.toggle())
  },
  toggle() {
    if (this.recorder) this.stop()
    else this.start()
  },
  async start() {
    const say = this.say
    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
      say("Recording is not supported by this browser.")
      return
    }
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      const type = MediaRecorder.isTypeSupported("audio/webm") ? "audio/webm" : ""
      this.recorder = type ? new MediaRecorder(this.stream, { mimeType: type }) : new MediaRecorder(this.stream)
      this.chunks = []
      this.recorder.ondataavailable = event => {
        if (event.data.size) this.chunks.push(event.data)
      }
      this.recorder.onstop = () => this.finish()
      this.recorder.start()
      this.el.textContent = "Stop & transcribe"
      this.el.dataset.recording = "true"
      say(`Recording… speak the task, then click again (${this.maxSeconds}s max).`)
      this.timer = setTimeout(() => this.stop(), this.maxSeconds * 1000)
    } catch (_) {
      this.reset()
      say("Could not use the microphone. Check the permission.")
    }
  },
  stop() {
    clearTimeout(this.timer)
    this.timer = null
    this.stream?.getTracks().forEach(track => track.stop())
    this.recorder?.stop()
  },
  async finish() {
    const say = this.say
    const blob = new Blob(this.chunks, { type: this.recorder.mimeType || "audio/webm" })
    this.reset()
    if (!blob.size) {
      say("Nothing was recorded. Try again.")
      return
    }
    say("Transcribing with ElevenLabs…")
    try {
      const response = await fetch("/api/voice/transcribe", {
        method: "POST",
        headers: { "content-type": blob.type || "audio/webm" },
        body: blob,
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) {
        say(data.error || `Transcription failed (HTTP ${response.status}).`)
        return
      }
      const input = document.querySelector(this.target)
      if (!input) {
        say("The form for this is not open. Open the panel first.")
        return
      }
      input.value = data.text
      input.dispatchEvent(new Event("input", { bubbles: true }))
      input.focus()
      say("Transcribed. Review the title before creating the issue.")
    } catch (_) {
      say("Could not reach the board. Check the server.")
    }
  },
  reset() {
    this.recorder = null
    this.stream = null
    this.chunks = []
    this.el.textContent = this.idleLabel
    delete this.el.dataset.recording
  },
  say(text) {
    const feedback = document.querySelector("#voice-feedback")
    if (feedback) feedback.textContent = text
  },
  destroyed() {
    clearTimeout(this.timer)
    this.stream?.getTracks().forEach(track => track.stop())
  },
}
