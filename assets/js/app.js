// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/agent_board"
import {BoardPanels} from "./hooks/board_panels"
import {BoardMenu} from "./hooks/board_menu"
import {BoardClock} from "./hooks/board_clock"
import {BoardKeyboard} from "./hooks/board_keyboard"
import {BoardFold} from "./hooks/board_fold"
import {Composer} from "./hooks/composer"
import {BoardConnection} from "./hooks/board_connection"
import {BoardRestart} from "./hooks/board_restart"
import {LogsSheet} from "./hooks/logs_sheet"
import {DataAge} from "./hooks/data_age"
import {ThemeToggle} from "./hooks/theme_toggle"
import {DailySummaryVoice} from "./hooks/daily_summary_voice"
import {ValueChange} from "./hooks/value_change"
import {BoardMotion} from "./hooks/board_motion"
import {VoiceCommand} from "./hooks/voice_command"
import {VoicePlayer} from "./hooks/voice_player"
import {VoicePresence} from "./hooks/voice_presence"
import {VoiceWispr} from "./hooks/voice_wispr"
import {TaskConversation} from "./hooks/task_conversation"
import {ImageViewer} from "./hooks/image_viewer"
import {voiceInputActive, voiceState} from "./voice_state"
import {localize} from "./i18n"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const boardResume = () => {
  const board = document.querySelector("#board-page")
  const repo = board?.querySelector("#repo-select select")?.value
  if (!repo) return null

  return {
    repo,
    merged: board.querySelectorAll("#merged-list .archive-row").length,
    tasks: Object.fromEntries([...board.querySelectorAll(".board-column[data-state]")]
      .map(lane => [lane.dataset.state, lane.querySelectorAll(".task-card").length])),
  }
}
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  // Read the mounted DOM on every connection so loaded pages survive a socket reconnect.
  params: () => ({
    _csrf_token: csrfToken,
    board_resume: boardResume(),
    // The last visit belongs to this browser: the server cannot know it.
    board_last_visit: localStorage.getItem("ab:last-visit"),
    board_message_seen: localStorage.getItem("ab:message-seen"),
    board_tz_offset: new Date().getTimezoneOffset(),
  }),
  hooks: {...colocatedHooks, DataAge, ThemeToggle, DailySummaryVoice, BoardMenu, BoardPanels, BoardClock, BoardConnection, BoardRestart, BoardKeyboard, BoardFold, Composer, ValueChange, BoardMotion, LogsSheet, VoiceCommand, VoicePlayer, VoicePresence, VoiceWispr, TaskConversation, ImageViewer},
  dom: {
    onBeforeElUpdated(from, to) {
      // The native modal lifecycle belongs to BoardPanels, while LiveView updates its content.
      if (from.matches("dialog.board-dialog")) to.toggleAttribute("open", from.open)
      // Header disclosures remain open while a broadcast refreshes the board.
      if (from.matches("[data-board-menu]")) to.toggleAttribute("open", from.open)
      if (from.matches("[data-mobile-fold]")) to.toggleAttribute("open", from.open)
    },
  },
})

// Show progress bar on live navigation and form submits
window.addEventListener("phx:page-loading-start", _info => {
  const theme = getComputedStyle(document.documentElement)
  topbar.config({barColors: {0: theme.getPropertyValue("--color-primary").trim()}, shadowColor: "transparent"})
  topbar.show(300)
})
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Remember when this visit ended; the next page load uses it for "since your
// last visit" and for the new markers. A crash keeps the older, honest time.
window.addEventListener("pagehide", () => {
  try { localStorage.setItem("ab:last-visit", new Date().toISOString()) } catch (_) {}
})

const rememberMessageSeen = (versions) => {
  try {
    const seen = JSON.parse(localStorage.getItem("ab:message-seen") || "{}")
    localStorage.setItem("ab:message-seen", JSON.stringify({...seen, ...versions}))
  } catch (_) {}
}

window.addEventListener("phx:message_seen", ({detail}) => {
  rememberMessageSeen({[String(detail.task_id)]: String(detail.version)})
  if (detail.quick) {
    requestAnimationFrame(() => {
      const inbox = document.querySelector("#message-inbox")
      if (!inbox?.open) return
      const next = inbox.querySelector(".ab-hub-row__read") ||
        inbox.querySelector(".ab-hub-menu__filters button[aria-pressed='true']")
      next?.focus({preventScroll: true})
    })
  }
})

window.addEventListener("phx:messages_seen", ({detail}) => {
  rememberMessageSeen(detail.versions)
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}


// The composer's voice pill follows the actual browser media phase.
// A path the owner copies from the board (a task's private context).
window.addEventListener("board:copy", ({detail}) => {
  navigator.clipboard?.writeText(detail?.text || "").catch(() => {})
})

window.addEventListener("board:voice-state", ({detail}) => {
  const pill = document.querySelector("#composer-voice")
  if (!pill) return
  const active = ["permission", "listening", "transcribing"].includes(detail.phase)
  pill.hidden = !active
  pill.dataset.phase = detail.phase
  const label = pill.querySelector("[data-voice-label]")
  if (label) {
    label.textContent = localize(detail.phase === "transcribing"
      ? "Transcrevendo…"
      : detail.phase === "permission" ? "Aguardando microfone…" : "Ouvindo…")
  }
})

// The typed chat line empties once the board took the words.
window.addEventListener("phx:voice_chat_clear", () => {
  const input = document.querySelector("#voice-chat-text")
  if (input) input.value = ""
})

// The browser's own voices vary a lot: prefer one in the exact language,
// then an enhanced or neural one, then any voice of the language family.
const bestBrowserVoice = (lang) => {
  const voices = window.speechSynthesis?.getVoices?.() || []
  if (!voices.length) return null
  const family = lang.slice(0, 2).toLowerCase()
  const quality = v => /premium|enhanced|natural|neural|google/i.test(v.name) ? 2 : (v.localService ? 1 : 0)
  const score = v => (v.lang.toLowerCase() === lang.toLowerCase() ? 10 : v.lang.toLowerCase().startsWith(family) ? 5 : 0) + quality(v)
  const best = voices.reduce((a, b) => (score(b) > score(a) ? b : a), voices[0])
  return score(best) >= 5 ? best : null
}
// Voices load asynchronously in some browsers; asking once warms the list.
window.speechSynthesis?.getVoices?.()

// Voice out: the server pushes the summary, the browser speaks it.
let browserSpeech = null
window.addEventListener("phx:speak", (event) => {
  const text = event.detail.text
  if (!text || voiceInputActive()) return
  if (!window.speechSynthesis || !window.SpeechSynthesisUtterance) {
    voiceState("error", "Fala indisponível", "Este navegador não consegue falar.", "browser-speech")
    return
  }
  browserSpeech = null
  window.speechSynthesis.cancel()
  const utterance = new SpeechSynthesisUtterance(text)
  browserSpeech = utterance
  // The language and volume are the owner's voice settings, not the
  // browser's locale: a Portuguese board is read in Portuguese.
  const panel = document.querySelector("#voice-panel")
  const volume = Number(panel?.dataset.volume)
  utterance.lang = event.detail.lang || panel?.dataset.lang || navigator.language || "pt-BR"
  const rate = Number(event.detail.rate)
  if (Number.isFinite(rate)) utterance.rate = rate
  const voice = bestBrowserVoice(utterance.lang)
  if (voice) utterance.voice = voice
  utterance.volume = Number.isFinite(volume) ? Math.min(Math.max(volume, 0), 100) / 100 : 1
  utterance.onstart = () => voiceState("speaking", "O agente está falando", event.detail.display || "Usando a voz do navegador.", "browser-speech")
  utterance.onend = () => {
    if (browserSpeech !== utterance) return
    browserSpeech = null
    voiceState("complete", "Terminei de falar", "Reprodução concluída.", "browser-speech")
    if (event.detail.listen) window.dispatchEvent(new CustomEvent("board:voice-start", {detail: {followup: true}}))
  }
  utterance.onerror = () => {
    if (browserSpeech !== utterance) return
    browserSpeech = null
    voiceState("error", "A fala não tocou", "Tente de novo ou confira o som do navegador.", "browser-speech")
  }
  voiceState("generating", "Preparando a fala", "Usando a voz do navegador.", "browser-speech")
  try {
    window.speechSynthesis.speak(utterance)
  } catch (_) {
    browserSpeech = null
    voiceState("error", "A fala não começou", "Tente de novo depois de interagir com a página.", "browser-speech")
  }
})

window.addEventListener("board:voice-control", ({detail}) => {
  if (browserSpeech && detail.source === "browser-speech") {
    browserSpeech = null
    window.speechSynthesis.cancel()
    voiceState("complete", "Fala interrompida", "A reprodução parou.", "browser-speech")
  }
})
