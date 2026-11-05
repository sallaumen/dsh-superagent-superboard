// Plays the ElevenLabs audio the server points at: voice previews, the
// spoken board status and the "voice selected" confirmation. The fetch lets
// the player show the server's real error (rejected key, usage limit, ...)
// instead of a generic audio failure.
export const VoicePlayer = {
  mounted() {
    this.audio = new Audio()
    this.objectUrl = null
    this.handleEvent("voice_play", ({ url }) => this.play(url))
  },
  async play(url) {
    const say = text => {
      const feedback = document.querySelector("#voice-feedback")
      if (feedback) feedback.textContent = text
    }
    try {
      say("Generating voice…")
      const response = await fetch(url)
      if (!response.ok) {
        let message = `Could not generate the voice (HTTP ${response.status}).`
        try {
          const data = await response.json()
          if (data.error) message = data.error
        } catch (_) {
          // not JSON; keep the status message
        }
        say(message)
        return
      }
      const blob = await response.blob()
      this.audio.pause()
      if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = URL.createObjectURL(blob)
      this.audio.src = this.objectUrl
      this.audio.onplaying = () => say("Playing voice…")
      this.audio.onended = () => say("Voice played.")
      this.audio.onerror = () => say("Could not play the audio.")
      await this.audio.play()
    } catch (_) {
      say("Could not reach the board. Check the server.")
    }
  },
  destroyed() {
    this.audio?.pause()
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
  },
}
