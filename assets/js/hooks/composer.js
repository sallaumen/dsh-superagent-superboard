// The composer submits on Cmd/Ctrl+Enter, like the panel's hint says.
export const Composer = {
  mounted() {
    this.onKey = event => {
      if (!(event.metaKey || event.ctrlKey) || event.key !== "Enter") return
      event.preventDefault()
      this.el.closest("form")?.requestSubmit()
    }
    this.onPaste = event => {
      const files = Array.from(event.clipboardData?.files || [])
      if (files.length === 0) return
      event.preventDefault()
      this.upload("attachments", files)
    }
    this.el.addEventListener("keydown", this.onKey)
    this.el.addEventListener("paste", this.onPaste)
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.onKey)
    this.el.removeEventListener("paste", this.onPaste)
  },
}
