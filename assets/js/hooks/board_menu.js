export const BoardMenu = {
  mounted() {
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
  },
  destroyed() {
    document.removeEventListener("pointerdown", this.closeOnOutside)
    document.removeEventListener("keydown", this.closeOnEscape)
  },
}
