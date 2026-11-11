// The composer submits on Cmd/Ctrl+Enter, like the panel's hint says. Enter
// in a field marked data-enter-click presses its button instead of sending
// the request (the private folder field).
export const Composer = {
  mounted() {
    this.form = this.el.closest("form")
    this.onFieldEnter = event => {
      const target = event.target.dataset?.enterClick
      if (!target || event.key !== "Enter") return
      event.preventDefault()
      document.getElementById(target)?.click()
    }
    this.form?.addEventListener("keydown", this.onFieldEnter)
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
    this.form?.removeEventListener("keydown", this.onFieldEnter)
    this.el.removeEventListener("keydown", this.onKey)
    this.el.removeEventListener("paste", this.onPaste)
  },
}
