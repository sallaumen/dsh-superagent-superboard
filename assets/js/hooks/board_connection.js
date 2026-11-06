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
  },
  disconnected() {
    const page = document.querySelector("#board-page")
    this.frozenAt = page?.dataset.syncAt || new Date().toISOString()
    sessionStorage.setItem("ab:disconnected-at", this.frozenAt)
    this.mark("down")
  },
  reconnected() {
    this.mark("live")
    sessionStorage.removeItem("ab:disconnected-at")
    this.pushEvent("board_reconnected", {since: this.frozenAt || null})
  },
  handleEvent(event) {
    if (event === "restart") this.reloadWhenBack()
  },
  // The server exits to boot the updated code; poll the same URL until it
  // answers again, then reload so the new assets and client are loaded.
  reloadWhenBack() {
    setTimeout(() => {
      const timer = setInterval(async () => {
        try {
          const response = await fetch(window.location.href, {
            method: "HEAD",
            cache: "no-store",
          })
          if (response.ok) {
            clearInterval(timer)
            window.location.reload()
          }
        } catch (_error) {
          // The old server is gone; the new one is still booting.
        }
      }, 1500)
      setTimeout(() => clearInterval(timer), 90000)
    }, 2500)
  },
  mark(state) {
    const page = document.querySelector("#board-page")
    if (page) page.dataset.connection = state
  },
}
