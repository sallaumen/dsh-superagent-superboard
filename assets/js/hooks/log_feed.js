// Follow new entries only while the reader is at the end of the log.
export const LogFeed = {
  mounted() {
    this.pinned = true
    this.onScroll = () => {
      this.pinned = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 32
    }
    this.el.addEventListener("scroll", this.onScroll, {passive: true})
    this.el.scrollTop = this.el.scrollHeight
  },
  updated() { if (this.pinned) this.el.scrollTop = this.el.scrollHeight },
  destroyed() { this.el.removeEventListener("scroll", this.onScroll) },
}
