// A click on Update/Restart is the only reliable "this server is going away"
// signal on the client: the pushed event can be lost when the VM stops. Keep
// the timestamp and let BoardConnection decide on disconnect.
export const BoardRestart = {
  mounted() {
    this.onClick = event => {
      const trigger = event.target.closest('[phx-click="update"], [phx-click="restart"]')
      if (trigger) sessionStorage.setItem("ab:restart-requested-at", String(Date.now()))
    }

    this.el.addEventListener("click", this.onClick)
  },
  destroyed() {
    this.el.removeEventListener("click", this.onClick)
  },
}
