// Reveal a new destination once. Refreshes keep focus and scroll where the operator left them.
export const SettingsNav = {
  mounted() {
    this.showDestination()
  },
  updated() {
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
  destroyed() {
    cancelAnimationFrame(this.frame)
  },
}
