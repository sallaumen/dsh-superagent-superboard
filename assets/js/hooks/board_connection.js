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

    // LiveView 1.2 hooks register server events through the core handleEvent
    // method; defining a handleEvent property overwrote it and warned on every
    // connect. The restart event only marks the tab; it reloads after the new boot.
    this.handleEvent("restart", () => {
      sessionStorage.setItem("ab:reload-after-restart", "1")
    })
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

  // Called only once the new server has answered the LiveView, so the reload
  // cannot land on a dead port; it fetches the new assets without an F5.
  reloadIfRestarted() {
    if (sessionStorage.getItem("ab:reload-after-restart") !== "1") return
    sessionStorage.removeItem("ab:reload-after-restart")
    window.location.reload()
  },
  mark(state) {
    const page = document.querySelector("#board-page")
    if (page) page.dataset.connection = state
  },
}
