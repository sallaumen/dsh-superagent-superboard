// A single outlet for the actual browser media phases. The voice presence
// title (role="status" in board_components/voice/presence.ex) is the only live region; the
// rest of that surface is visual and interactive.
import {localize} from "./i18n"

let current = {phase: "idle", source: ""}

export const voiceInputActive = () =>
  current.source === "command-recorder" &&
  ["permission", "listening", "transcribing"].includes(current.phase)

export const interruptVoiceOutput = () => {
  window.dispatchEvent(new CustomEvent("board:voice-control", {detail: {source: "elevenlabs"}}))
}

export const voiceState = (phase, title, detail = "", source = "") => {
  title = localize(title)
  detail = localize(detail)
  current = {phase, source}
  window.dispatchEvent(new CustomEvent("board:voice-state", {detail: {phase, title, detail, source}}))
}
