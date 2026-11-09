// On a phone the secondary lanes (Mesclados, Vazão) start folded to a single
// line; on wider screens they are always open. Presentation only: the server
// renders the same content and the disclosure stays a native details.
export const BoardFold = {
  mounted() {
    this.media = window.matchMedia("(max-width: 640px)")
    this.userToggled = false
    this.apply()
    this.onChange = () => {
      this.userToggled = false
      this.apply()
    }
    this.media.addEventListener("change", this.onChange)
    this.el.addEventListener("toggle", () => {
      if (!this.ready) return
      this.userToggled = this.media.matches
    })
  },

  updated() {
    this.apply()
  },

  destroyed() {
    if (this.media) this.media.removeEventListener("change", this.onChange)
  },

  apply() {
    if (!this.media) return
    if (!this.media.matches) {
      this.el.open = true
    } else if (!this.userToggled) {
      this.el.open = false
    }
    this.ready = true
    this.el.dataset.ready = "true"
  },
}
