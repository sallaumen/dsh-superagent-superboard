// The head script syncs aria-pressed before the settings panel is mounted.
// This hook repeats that sync after LiveView inserts or patches the control,
// so the active theme is announced on load and stays correct after a patch.
const sync = (el) => {
  const root = document.documentElement
  const selected = root.dataset.themeSource === "system" ? "system" : root.dataset.theme
  el.querySelectorAll("[data-phx-theme]").forEach(button => {
    button.setAttribute("aria-pressed", String(button.dataset.phxTheme === selected))
  })
}

export const ThemeToggle = {
  mounted() {
    this.onTheme = () => sync(this.el)
    this.onStorage = (event) => {
      if (event.key === "phx:theme") sync(this.el)
    }
    window.addEventListener("phx:set-theme", this.onTheme)
    window.addEventListener("storage", this.onStorage)
    sync(this.el)
  },
  updated() { sync(this.el) },
  destroyed() {
    window.removeEventListener("phx:set-theme", this.onTheme)
    window.removeEventListener("storage", this.onStorage)
  },
}
