import {voiceInputActive, voiceState} from "../voice_state"

// The server chooses the speech URL. Playback state follows the audio element,
// never the request or the presence of an ElevenLabs key alone.
export const VoicePlayer = {
  mounted() {
    this.audio = new Audio()
    this.objectUrl = null
    this.generation = 0
    this.onControl = ({detail}) => {
      if (detail.source === "elevenlabs" && this.active) {
        this.cancel()
        voiceState("complete", "Voice stopped", "Playback was stopped.", "elevenlabs")
      }
    }
    window.addEventListener("board:voice-control", this.onControl)
    this.handleEvent("voice_play", ({url}) => this.play(url))
  },
  async play(url) {
    if (voiceInputActive()) return
    this.cancel()
    const generation = ++this.generation
    this.active = true
    this.abort = new AbortController()
    voiceState("generating", "Preparing agent voice", "Waiting for ElevenLabs audio.", "elevenlabs")

    let blob
    try {
      const response = await fetch(url, {signal: this.abort.signal})
      if (generation !== this.generation) return
      if (!response.ok) {
        let message = `Voice request failed (HTTP ${response.status}).`
        try {
          const data = await response.json()
          if (data.error) message = data.error
        } catch (_) {
          // The status still identifies the failed request.
        }
        this.active = false
        voiceState("error", "Voice could not be prepared", message, "elevenlabs")
        return
      }
      blob = await response.blob()
      if (generation !== this.generation) return
    } catch (error) {
      if (generation !== this.generation || error?.name === "AbortError") return
      this.active = false
      voiceState("error", "Voice service is unreachable", "Check the board connection and try again.", "elevenlabs")
      return
    }

    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = URL.createObjectURL(blob)
    this.audio.src = this.objectUrl
    this.audio.onplaying = () => {
      if (generation === this.generation) voiceState("speaking", "Agent is speaking", "ElevenLabs audio is playing.", "elevenlabs")
    }
    this.audio.onended = () => {
      if (generation !== this.generation) return
      this.active = false
      voiceState("complete", "Agent finished speaking", "Playback finished.", "elevenlabs")
    }
    this.audio.onerror = () => {
      if (generation !== this.generation) return
      this.active = false
      voiceState("error", "Audio could not play", "Check the audio format or browser policy.", "elevenlabs")
    }

    try {
      await this.audio.play()
    } catch (error) {
      if (generation !== this.generation) return
      this.active = false
      voiceState(
        "error",
        "Audio could not play",
        error?.name === "NotAllowedError"
          ? "The browser blocked playback. Try again after interacting with the page."
          : "Check the browser sound and try again.",
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
  destroyed() {
    window.removeEventListener("board:voice-control", this.onControl)
    this.cancel()
  },
}
