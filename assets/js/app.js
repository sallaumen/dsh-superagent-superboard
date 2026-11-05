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
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, DataAge, BoardPanels, SettingsMenu},
  dom: {
    onBeforeElUpdated(from, to) {
      // The native modal lifecycle belongs to BoardPanels, while LiveView updates its content.
      if (from.matches("dialog.board-dialog")) to.toggleAttribute("open", from.open)
      // Native disclosures should remain open while a broadcast refreshes their records.
      if (from.matches("#merged-history, #board-settings")) to.toggleAttribute("open", from.open)
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


const voiceFeedback = text => {
  const status = document.querySelector("#voice-feedback")
  if (status) status.textContent = text
}

// Voice out: the server pushes the summary, the browser speaks it.
window.addEventListener("phx:speak", (event) => {
  const text = event.detail.text;
  if (!text) return;
  if (!window.speechSynthesis || !window.SpeechSynthesisUtterance) {
    voiceFeedback("Speech playback is not supported by this browser.");
    return;
  }
  window.speechSynthesis.cancel();
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.lang = navigator.language || "en-US";
  utterance.onend = () => voiceFeedback("Status spoken.");
  utterance.onerror = () => voiceFeedback("Could not play the status. Try again.");
  voiceFeedback("Speaking board status…");
  window.speechSynthesis.speak(utterance);
});

// Voice in: dictate a task title into the form.
window.addEventListener("phx:dictate", () => {
  const Rec = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!Rec) {
    voiceFeedback("Dictation is not supported by this browser. Type the task title below.");
    return;
  }
  const rec = new Rec();
  rec.lang = navigator.language || "en-US";
  rec.interimResults = false;
  rec.onresult = (event) => {
    const input = document.querySelector("#task-title");
    if (input) {
      input.value = event.results[0][0].transcript;
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.focus();
      voiceFeedback("Title transcribed. Review it before creating the issue.");
    }
  };
  rec.onerror = () => voiceFeedback("Could not hear the title. Check microphone permission or type it below.");
  voiceFeedback("Listening for a task title…");
  rec.start();
});
