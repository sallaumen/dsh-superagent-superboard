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
import {DataAge} from "./hooks/data_age"
import {SettingsMenu} from "./hooks/settings_menu"
import {VoicePlayer} from "./hooks/voice_player"
import {VoicePresence} from "./hooks/voice_presence"
import {VoiceRecorder} from "./hooks/voice_recorder"
import {interruptVoiceOutput, voiceInputActive, voiceState} from "./voice_state"
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
  params: () => ({_csrf_token: csrfToken, board_resume: boardResume()}),
  hooks: {...colocatedHooks, DataAge, BoardPanels, SettingsMenu, VoicePlayer, VoicePresence, VoiceRecorder},
  dom: {
    onBeforeElUpdated(from, to) {
      // The native modal lifecycle belongs to BoardPanels, while LiveView updates its content.
      if (from.matches("dialog.board-dialog")) to.toggleAttribute("open", from.open)
      // Settings should remain open while a broadcast refreshes the board.
      if (from.matches("#board-settings")) to.toggleAttribute("open", from.open)
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


// Voice out: the server pushes the summary, the browser speaks it.
let browserSpeech = null
window.addEventListener("phx:speak", (event) => {
  const text = event.detail.text
  if (!text || voiceInputActive()) return
  if (!window.speechSynthesis || !window.SpeechSynthesisUtterance) {
    voiceState("error", "Speech is unavailable", "This browser cannot play the board status.", "browser-speech")
    return
  }
  browserSpeech = null
  window.speechSynthesis.cancel()
  const utterance = new SpeechSynthesisUtterance(text)
  browserSpeech = utterance
  utterance.lang = navigator.language || "en-US"
  utterance.onstart = () => voiceState("speaking", "Speaking board status", "Browser voice is playing.", "browser-speech")
  utterance.onend = () => {
    if (browserSpeech !== utterance) return
    browserSpeech = null
    voiceState("complete", "Board status spoken", "Playback finished.", "browser-speech")
  }
  utterance.onerror = () => {
    if (browserSpeech !== utterance) return
    browserSpeech = null
    voiceState("error", "Speech could not play", "Try again or check the browser sound.", "browser-speech")
  }
  voiceState("generating", "Preparing board status", "Using the browser voice.", "browser-speech")
  try {
    window.speechSynthesis.speak(utterance)
  } catch (_) {
    browserSpeech = null
    voiceState("error", "Speech could not start", "Try again after interacting with the page.", "browser-speech")
  }
})

// Voice in: dictate a task title into the form.
let browserRecognition = null
window.addEventListener("phx:dictate", () => {
  interruptVoiceOutput()
  const previousRecognition = browserRecognition
  browserRecognition = null
  previousRecognition?.abort()
  const Rec = window.SpeechRecognition || window.webkitSpeechRecognition
  if (!Rec) {
    voiceState("error", "Dictation is unavailable", "Type the task title in New task.", "browser-dictation")
    return
  }
  const rec = new Rec()
  browserRecognition = rec
  rec.hasResult = false
  rec.hadError = false
  rec.lang = navigator.language || "en-US"
  rec.interimResults = false
  rec.onstart = () => {
    if (browserRecognition === rec) voiceState("listening", "Listening for a task title", "Speak now. Dictation will fill an editable field.", "browser-dictation")
  }
  rec.onresult = (event) => {
    if (browserRecognition !== rec) return
    rec.hasResult = true
    const input = document.querySelector("#task-title")
    if (input) {
      input.value = event.results[0][0].transcript
      input.dispatchEvent(new Event("input", { bubbles: true }))
      input.focus()
      voiceState("complete", "Title transcribed", "Review it before creating the task.", "browser-dictation")
    } else {
      voiceState("error", "New task is closed", "Open New task to use the dictated title.", "browser-dictation")
    }
  }
  rec.onerror = () => {
    if (browserRecognition !== rec) return
    rec.hadError = true
    voiceState("error", "Could not hear the title", "Check microphone permission or type it instead.", "browser-dictation")
  }
  rec.onend = () => {
    if (browserRecognition !== rec) return
    browserRecognition = null
    if (!rec.hasResult && !rec.hadError) {
      voiceState("complete", "Dictation ended", "No title was captured. Try again or type it.", "browser-dictation")
    }
  }
  voiceState("permission", "Waiting for microphone", "Allow access to dictate a task title.", "browser-dictation")
  try { rec.start() } catch (_) {
    browserRecognition = null
    voiceState("error", "Could not start dictation", "Type the title in New task.", "browser-dictation")
  }
})

window.addEventListener("board:voice-control", ({detail}) => {
  if (browserSpeech && detail.source === "browser-speech") {
    browserSpeech = null
    window.speechSynthesis.cancel()
    voiceState("complete", "Speech stopped", "Playback was stopped.", "browser-speech")
  }
  if (browserRecognition && detail.source === "browser-dictation") {
    if (detail.phase === "permission") {
      browserRecognition.abort()
      browserRecognition = null
      voiceState("complete", "Dictation cancelled", "Nothing was sent.", "browser-dictation")
    } else {
      voiceState("transcribing", "Finishing dictation", "The title will remain editable.", "browser-dictation")
      browserRecognition.stop()
    }
  }
})

document.addEventListener("close", event => {
  if (!event.target.matches?.(".board-dialog") || !browserRecognition) return
  const rec = browserRecognition
  browserRecognition = null
  rec.abort()
  voiceState("idle", "", "", "browser-dictation")
}, true)
