// Reveal the selected section within the horizontal strip. Do not move focus,
// scroll the section content, or undo manual scrolling on a board refresh.
export const SettingsNav = {
  mounted() {
    this.observer = new ResizeObserver(() => this.reveal())
    this.observer.observe(this.el)
    this.reveal()
  },
  updated() { this.reveal() },
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
  destroyed() { this.observer.disconnect() },
}
