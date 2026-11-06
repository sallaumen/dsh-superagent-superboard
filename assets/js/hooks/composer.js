// The composer submits on Cmd/Ctrl+Enter, like the panel's hint says.
export const Composer = {
  mounted() {
    this.onKey = event => {
      if (!(event.metaKey || event.ctrlKey) || event.key !== "Enter") return
      event.preventDefault()
      this.el.closest("form")?.requestSubmit()
    }
    this.el.addEventListener("keydown", this.onKey)
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.onKey)
  },
}
