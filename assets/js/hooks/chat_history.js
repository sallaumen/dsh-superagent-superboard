// Follow a new answer only while the reader is at the end of the conversation.
export const ChatHistory = {
  mounted() {
    this.pinned = true
    this.last = this.el.lastElementChild?.id
    this.onScroll = () => {
      this.pinned = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 40
    }
    this.open = false
    this.onContext = () => {
      const open = this.el.closest("dialog")?.open
      if (open && !this.open && this.pinned) this.scrollToLatest()
      this.open = open
    }
    window.addEventListener("board:voice-context", this.onContext)
    this.el.addEventListener("scroll", this.onScroll, {passive: true})
    this.scrollToLatest()
  },
  updated() {
    const latest = this.el.lastElementChild?.id
    if (latest !== this.last && (this.pinned || this.el.lastElementChild?.dataset.role === "owner")) {
      this.scrollToLatest()
    }
    this.last = latest
  },
  scrollToLatest() {
    cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => { this.el.scrollTop = this.el.scrollHeight })
  },
  destroyed() {
    cancelAnimationFrame(this.frame)
    window.removeEventListener("board:voice-context", this.onContext)
    this.el.removeEventListener("scroll", this.onScroll)
  },
}
