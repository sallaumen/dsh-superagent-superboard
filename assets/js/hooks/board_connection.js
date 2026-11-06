// The socket state is client-side knowledge: the server cannot render
// "reconnecting" while it is not connected. The beacon and the frozen banner
// read this attribute; the server is told on reconnect so it can count changes.
export const BoardConnection = {
  mounted() {
    this.mark("live")
  },
  disconnected() {
    this.mark("down")
  },
  reconnected() {
    this.mark("live")
    this.pushEvent("board_reconnected", {})
  },
  mark(state) {
    const page = document.querySelector("#board-page")
    if (page) page.dataset.connection = state
  },
}
