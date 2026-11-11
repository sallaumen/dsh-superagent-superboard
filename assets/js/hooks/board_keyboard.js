// The board's one keyboard map. It never steals keys while a field or a
// dialog owns them; Escape belongs to the layer, not here.
export const BoardKeyboard = {
  mounted() {
    this.onKey = event => this.handle(event)
    document.addEventListener("keydown", this.onKey)
  },
  handle(event) {
    if (!event.isTrusted || event.defaultPrevented || event.isComposing) return
    if (event.metaKey || event.ctrlKey || event.altKey) return

    const target = event.target
    const typing = target?.closest?.("input, textarea, select, [contenteditable='true']")
    const dialog = document.querySelector(".board-dialog[open]")
    const menu = document.querySelector("[data-board-menu][open]")
    if (typing || menu) return
    if (dialog && event.key !== "Escape") return

    const rows = [...document.querySelectorAll("#board-page [data-task]")]
    const current = document.activeElement?.closest?.("[data-task]")
    const index = rows.indexOf(current)

    if (event.key === "j" || event.key === "J") {
      if (rows.length === 0) return
      event.preventDefault()
      rows[Math.min(rows.length - 1, index < 0 ? 0 : index + 1)]?.focus({preventScroll: false})
      return
    }

    if (event.key === "k" || event.key === "K") {
      if (rows.length === 0) return
      event.preventDefault()
      rows[Math.max(0, index < 0 ? rows.length - 1 : index - 1)]?.focus({preventScroll: false})
      return
    }

    if (event.key === "Enter" && current) {
      // A link or a button inside the card owns its own Enter; the card
      // itself opens the task through its title button (a queue row is the
      // button).
      const action = target?.closest?.("a, button")
      if (action && action !== current) return
      event.preventDefault()
      ;(current.querySelector("button[phx-click=open]") ?? current).click()
      return
    }

    if (event.key === "n" || event.key === "N") {
      event.preventDefault()
      document.querySelector("#open-create")?.click()
      return
    }

    if (event.key === "v" || event.key === "V") {
      event.preventDefault()
      const composerOpen = document.querySelector("#panel-composer[open]")
      if (composerOpen) {
        window.dispatchEvent(new Event("board:voice-start"))
      } else {
        document.querySelector("#open-create")?.click()
        setTimeout(() => window.dispatchEvent(new Event("board:voice-start")), 350)
      }
      return
    }

    if (/^[1-5]$/.test(event.key)) {
      const inspector = document.querySelector("#conversation")
      if (!inspector) return
      event.preventDefault()
      const tabs = [...inspector.querySelectorAll(".ab-tab")]
      tabs[Number(event.key) - 1]?.click()
      return
    }

    if (event.key === "?") {
      event.preventDefault()
      document.querySelector("#open-shortcuts")?.click()
    }
  },
  destroyed() {
    document.removeEventListener("keydown", this.onKey)
  },
}
