// A single visual outlet for the actual browser media phases. The header
// remains the only live region; the large surface is visual and interactive.
let current = {phase: "idle", source: ""}

export const voiceInputActive = () =>
  current.source === "command-recorder" &&
  ["permission", "listening", "transcribing"].includes(current.phase)

export const interruptVoiceOutput = () => {
  for (const source of ["elevenlabs", "browser-speech"]) {
    window.dispatchEvent(new CustomEvent("board:voice-control", {detail: {source}}))
  }
}

export const voiceState = (phase, title, detail = "", source = "") => {
  current = {phase, source}
  const feedback = document.querySelector("#voice-feedback")
  if (feedback) feedback.textContent = [title, detail].filter(Boolean).join(" ")
  window.dispatchEvent(new CustomEvent("board:voice-state", {detail: {phase, title, detail, source}}))
}
