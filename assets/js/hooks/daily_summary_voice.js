// The summary of the day is spoken once, by a board the owner is at. A tab the
// owner has interacted with asks the server for it; a tab nobody touched (a
// preview, a monitor taking screenshots, a page whose audio the browser would
// block) waits for the first click or key and never spends the claim. Among
// the tabs that ask, the server's conditional update picks one.
let activated = false
const markActive = () => { activated = true }

if (typeof window !== "undefined") {
  window.addEventListener("pointerdown", markActive, {capture: true})
  window.addEventListener("keydown", markActive, {capture: true})
}

// Only an input event this page saw counts. `navigator.userActivation` is not
// trusted: under automation WebKit reports it active with no click (observed in
// Playwright's WebKit 26.6), and the monitor's previews are automated WebKit.
export const hasBeenActive = seen => seen === true

// The click that dismisses the summary is not a request to hear it.
export const dismissing = target => Boolean(target?.closest?.("[data-daily-dismiss]"))

export const DailySummaryVoice = {
  mounted() { this.ask() },
  updated() { this.ask() },
  destroyed() { this.stopWaiting() },
  ask() {
    const id = this.el.dataset.id
    if (this.el.dataset.spoken !== "false" || this.asked === id) return
    if (hasBeenActive(activated)) return this.claim(id)
    if (this.waiting) return

    this.waiting = event => {
      this.stopWaiting()
      if (dismissing(event.target)) { this.asked = id; return }
      this.claim(id)
    }
    window.addEventListener("pointerdown", this.waiting, {capture: true})
    window.addEventListener("keydown", this.waiting, {capture: true})
  },
  claim(id) {
    this.asked = id
    this.pushEvent("daily_summary_claim", {id})
  },
  stopWaiting() {
    if (!this.waiting) return
    window.removeEventListener("pointerdown", this.waiting, {capture: true})
    window.removeEventListener("keydown", this.waiting, {capture: true})
    this.waiting = null
  },
}
