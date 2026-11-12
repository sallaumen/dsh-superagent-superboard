// Settings → Costs moves only when what it shows was read again: the owner
// opened the section, or changed the page, the window or a filter that
// reloads (`data-motion-view`, the component's `loaded` key). A broadcast
// re-renders the same reading, so it moves nothing. Then the daily bars rise
// from the baseline in one left-to-right sweep, each meter goes from its old
// width to the new one, and a tile value that changed tints.

const RISE = "cubic-bezier(0.22, 1, 0.36, 1)" // kit.reveal: almost all travel early, then hold
const METER = "cubic-bezier(0.2, 0, 0, 1)" // m3.standard: an in-place value
const SWEEP = 240 // the whole chart starts within this, whatever the window (7, 30 or 90 bars)

export const duration = (px, weight = 1) => Math.round(Math.min(520, Math.max(70, (70 + 10 * Math.sqrt(px)) * weight)))
// The i-th of n bars starts this late: one sweep, not n entrances.
export const sweepDelay = (i, n) => (n > 1 ? Math.round((i * SWEEP) / (n - 1)) : 0)
// A meter that was w0 % and is now w1 %: scale from w0 / w1; from nothing when new.
export const meterFrom = (w0, w1) => (w1 > 0 && w0 >= 0 ? Math.min(w0 / w1, 4) : 0)

const quiet = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches
const percent = el => parseFloat(el.style.width) || 0

export const CostsMotion = {
  mounted() {
    this.view = this.el.dataset.motionView
    this.snapshot = this.read()
    if (this.view && !quiet()) this.play(null)
  },
  beforeUpdate() {
    this.snapshot = this.read()
  },
  updated() {
    const view = this.el.dataset.motionView
    const changed = view !== this.view
    this.view = view
    if (changed && view && !quiet()) this.play(this.snapshot)
  },

  read() {
    const meters = {}
    const values = {}
    this.el.querySelectorAll(".ab-costs__tile[id]").forEach(tile => {
      const meter = tile.querySelector(".ab-costs__meter span")
      if (meter) meters[tile.id] = percent(meter)
      const value = tile.querySelector(".ab-costs__tile-value")
      if (value) values[tile.id] = value.textContent.trim()
    })
    return {meters, values}
  },

  play(before) {
    this.el.querySelectorAll(".ab-costs__chart").forEach(chart => this.sweep(chart))
    this.el.querySelectorAll(".ab-costs__tile[id]").forEach(tile => {
      const meter = tile.querySelector(".ab-costs__meter span")
      if (meter) {
        const from = before && tile.id in before.meters ? meterFrom(before.meters[tile.id], percent(meter)) : 0
        if (from !== 1) meter.animate([{transform: `scaleX(${from})`}, {transform: "none"}], {duration: 200, easing: METER})
      }
      const value = tile.querySelector(".ab-costs__tile-value")
      if (value && before && tile.id in before.values && before.values[tile.id] !== value.textContent.trim()) {
        value.classList.remove("is-changed")
        void value.offsetWidth
        value.classList.add("is-changed")
      }
    })
  },
  // Each stacked bar grows as one: every segment scales from the stack's
  // baseline, so the upper segment does not float while the lower one grows.
  // The sweep spreads over the days that have a bar: two spent days in a
  // 30-day window must not wait for 28 empty ones.
  sweep(chart) {
    const days = Array.from(chart.querySelectorAll(".ab-costs__stack"))
      .map(stack => ({base: stack.getBoundingClientRect().bottom,
                      segs: Array.from(stack.querySelectorAll(".ab-costs__seg"))
                        .map(seg => ({seg, rect: seg.getBoundingClientRect()}))
                        .filter(({rect}) => rect.height > 0)}))
      .filter(day => day.segs.length)
    days.forEach(({base, segs}, i) => {
      segs.forEach(({seg, rect}) => {
        seg.style.transformOrigin = `50% ${base - rect.top}px`
        seg.animate([{transform: "scaleY(0)"}, {transform: "none"}],
          {duration: duration(base - rect.top), easing: RISE, delay: sweepDelay(i, days.length), fill: "backwards"})
      })
    })
  },
}
