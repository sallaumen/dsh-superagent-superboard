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
      if (event.key !== "Enter" || event.isComposing || event.defaultPrevented) return
      if (!(event.metaKey || event.ctrlKey)) {
        // Committing a title edit with Enter is not consent to publish an issue.
        if (event.target.matches('input[type="text"]')) event.preventDefault()
        return
      }
      if (event.target !== this.el && !event.target.matches('textarea[name^="clarify["]')) return
      event.preventDefault()
      const submit = this.form?.querySelector('button[type="submit"]')
      if (submit && !submit.disabled && !event.repeat) this.form.requestSubmit(submit)
    }
    this.onPaste = event => {
      const files = Array.from(event.clipboardData?.files || [])
      if (files.length === 0) return
      event.preventDefault()
      this.upload("attachments", files)
    }
    this.form?.addEventListener("keydown", this.onKey)
    this.el.addEventListener("paste", this.onPaste)
  },
  destroyed() {
    this.form?.removeEventListener("keydown", this.onFieldEnter)
    this.form?.removeEventListener("keydown", this.onKey)
    this.el.removeEventListener("paste", this.onPaste)
  },
}
