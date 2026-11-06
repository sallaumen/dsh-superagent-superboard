// The socket state is client-side knowledge: the server cannot render
// "reconnecting" while it is not connected. The beacon and the frozen banner
// read this attribute; the server is told on reconnect so it can count changes.
export const BoardConnection = {
  mounted() {
    this.mark("live")
    // A reconnect that remounts the view does not call reconnected(); the
    // frozen time survives in the tab so the server can still count changes.
    const since = sessionStorage.getItem("ab:disconnected-at")
    if (since) {
      sessionStorage.removeItem("ab:disconnected-at")
      setTimeout(() => this.pushEvent("board_reconnected", {since}), 600)
    }

    this.reloadIfRestarted()
  },
  disconnected() {
    const page = document.querySelector("#board-page")
    this.frozenAt = page?.dataset.syncAt || new Date().toISOString()
    sessionStorage.setItem("ab:disconnected-at", this.frozenAt)

    // A click on Update/Restart is the reliable signal that the server is
    // going away; the pushed event can be lost during the VM stop.
    const requested = Number(sessionStorage.getItem("ab:restart-requested-at") || 0)
    if (requested && Date.now() - requested < 30000) {
      sessionStorage.setItem("ab:reload-after-restart", "1")
    }
    sessionStorage.removeItem("ab:restart-requested-at")

    this.mark("down")
  },
  reconnected() {
    this.mark("live")
    sessionStorage.removeItem("ab:disconnected-at")
    this.pushEvent("board_reconnected", {since: this.frozenAt || null})
    this.reloadIfRestarted()
  },
  handleEvent(event) {
    if (event === "restart") sessionStorage.setItem("ab:reload-after-restart", "1")
  },
  // A reload can catch a socket that is still closing and leave the browser
  // on chrome-error. The new server has already answered the LiveView; give
  // the person the explicit reload that also fetches the new assets.
  reloadIfRestarted() {
    if (sessionStorage.getItem("ab:reload-after-restart") !== "1") return
    sessionStorage.removeItem("ab:reload-after-restart")
    setTimeout(() => this.showRestartNotice(), 500)
  },
  showRestartNotice() {
    if (document.querySelector(".ab-reload-notice")) return
    const notice = document.createElement("div")
    notice.className = "ab-reload-notice"
    notice.setAttribute("role", "status")
    notice.innerHTML =
      '<span>Servidor atualizado.</span><button type="button" class="ab-btn ab-btn--sm ab-btn--primary">Recarregar</button>'
    notice.querySelector("button").addEventListener("click", () => window.location.reload())
    document.body.appendChild(notice)
  },
  mark(state) {
    const page = document.querySelector("#board-page")
    if (page) page.dataset.connection = state
  },
}
