export const BoardMenu = {
  mounted() {
    this.closePeers = () => {
      if (!this.el.open) return
      document.querySelectorAll('[data-board-menu][open]').forEach(menu => {
        if (menu !== this.el) menu.open = false
      })
    }
    this.closeOnOutside = (event) => {
      if (document.querySelector(".board-dialog[open]")) return
      if (!this.el.contains(event.target)) this.el.open = false
    }
    this.closeOnEscape = (event) => {
      if (event.key !== "Escape" || !this.el.open || document.querySelector(".board-dialog[open]")) return
      this.el.open = false
      this.el.querySelector("summary")?.focus({preventScroll: true})
      event.preventDefault()
    }
    document.addEventListener("pointerdown", this.closeOnOutside)
    document.addEventListener("keydown", this.closeOnEscape)
    this.el.addEventListener("toggle", this.closePeers)
    this.closeOnNavigate = (event) => {
      if (event.target.closest("[data-board-menu-link]")) this.el.open = false
    }
    this.el.addEventListener("click", this.closeOnNavigate)
    this.bindFolds()
    this.restoreFolds()
  },
  updated() {
    // A version check re-renders the panel; keep the fold the person opened.
    this.bindFolds()
    this.restoreFolds()
  },
  bindFolds() {
    this.el.querySelectorAll("details.settings-fold").forEach(fold => {
      if (fold.dataset.foldBound) return
      fold.dataset.foldBound = "1"
      fold.addEventListener("toggle", () => {
        sessionStorage.setItem(`ab:fold:${fold.id}`, fold.open ? "1" : "0")
      })
    })
  },
  restoreFolds() {
    this.el.querySelectorAll("details.settings-fold").forEach(fold => {
      const stored = sessionStorage.getItem(`ab:fold:${fold.id}`)
      if (stored === "1" && !fold.open) fold.open = true
      if (stored === "0" && fold.open) fold.open = false
    })
  },
  destroyed() {
    document.removeEventListener("pointerdown", this.closeOnOutside)
    document.removeEventListener("keydown", this.closeOnEscape)
    this.el.removeEventListener("toggle", this.closePeers)
    this.el.removeEventListener("click", this.closeOnNavigate)
  },
}
