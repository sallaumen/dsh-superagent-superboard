// Reveal a new destination once. Refreshes keep focus and scroll where the operator left them.
export const SettingsNav = {
  mounted() {
    this.observer = new ResizeObserver(() => this.reveal())
    this.observer.observe(this.el)
    this.reveal()
    this.showDestination()
  },
  updated() {
    this.reveal()
    this.showDestination()
  },
  showDestination() {
    const location = this.el.dataset.location
    if (location === this.location) return
    this.location = location
    cancelAnimationFrame(this.frame)
    if (!location) return
    this.frame = requestAnimationFrame(() => {
      const content = document.getElementById("settings-current-section")
      if (!content) return
      const target = content.querySelector('[data-settings-target="true"]:not([hidden])')
      if (target?.getClientRects().length) {
        content.scrollTop += target.getBoundingClientRect().top - content.getBoundingClientRect().top - 8
      } else if (!window.location.hash) {
        content.scrollTop = 0
      }
    })
  },
  reveal() {
    const item = this.el.querySelector('[aria-current="page"]')
    const width = this.el.clientWidth
    const section = item?.getAttribute("phx-value-section")
    if (width === this.width && section === this.section) return
    this.width = width
    this.section = section
    if (!width || !item || this.el.scrollWidth <= width) return
    const strip = this.el.getBoundingClientRect()
    const rect = item.getBoundingClientRect()
    if (rect.left < strip.left) this.el.scrollLeft += rect.left - strip.left
    else if (rect.right > strip.right) this.el.scrollLeft += rect.right - strip.right
  },
  destroyed() {
    this.observer.disconnect()
    cancelAnimationFrame(this.frame)
  },
}
