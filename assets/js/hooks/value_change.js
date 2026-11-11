// A value that changed gets one short tint. The same value rendered again (a
// broadcast that changed something else) gets nothing: the DOM keeps the
// element, this hook keeps the last values, and only a difference pulses.
// "?" is not a value: the runner's first answer after the page opened is a
// reading, not a change. A count that rose is marked `is-up`, so a badge can
// say "something new" while a count the owner brought down stays quiet.
// The current hour's sparkline bar grows from its old height when its hour
// is the same and its count rose; a new hour is a cut.
export const changedKeys = (previous, next) =>
  Object.keys(next).filter(key => key in previous && previous[key] !== "?" && previous[key] !== next[key])

export const rose = (from, to) => Number(to) > Number(from)

// "19:00–19:48: 2" → "19:00": the hour a bar stands for. The current hour's
// label ends at the minute it was computed, so only its start identifies it.
export const bucket = title => title.split("–")[0]

const GROW = "cubic-bezier(0.2, 0, 0, 1)" // m3.standard: an in-place value
const quiet = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches

export const ValueChange = {
  mounted() {
    this.values = this.read()
    this.bars = this.readBars()
  },
  updated() {
    const next = this.read()
    for (const key of changedKeys(this.values, next)) this.pulse(key, rose(this.values[key], next[key]))
    this.values = next
    const bars = this.readBars()
    if (!quiet()) this.grow(this.bars, bars)
    this.bars = bars
  },
  nodes() {
    const nodes = Array.from(this.el.querySelectorAll("[data-key]"))
    return this.el.dataset.key ? [this.el, ...nodes] : nodes
  },
  read() {
    return Object.fromEntries(this.nodes().map(node => [node.dataset.key, node.dataset.value]))
  },
  pulse(key, up) {
    const node = this.nodes().find(n => n.dataset.key === key)
    if (!node) return
    node.classList.remove("is-changed", "is-up")
    void node.offsetWidth
    node.classList.add("is-changed")
    node.classList.toggle("is-up", up)
  },
  readBars() {
    const bars = {}
    this.el.querySelectorAll(".ab-flow__spark").forEach(svg => {
      const tile = svg.closest("[id]")?.id
      const now = svg.querySelector("rect.is-now")
      const title = now?.querySelector("title")?.textContent
      if (tile && now && title) bars[tile] = {bucket: bucket(title), h: Number(now.getAttribute("height")), rect: now}
    })
    return bars
  },
  grow(before, after) {
    Object.entries(after).forEach(([tile, bar]) => {
      const old = before[tile]
      if (!old || old.bucket !== bar.bucket || !(bar.h > old.h)) return
      bar.rect.animate([{transform: `scaleY(${old.h / bar.h})`}, {transform: "none"}], {duration: 180, easing: GROW})
    })
  },
}
