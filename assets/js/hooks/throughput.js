// A throughput value that changed gets one short tint. The same value rendered
// again (a broadcast that changed something else) gets nothing: the DOM keeps
// the element, this hook keeps the last values, and only a difference pulses.
// "?" is not a value: the runner's first answer after the page opened is a
// reading, not a change.
export const changedKeys = (previous, next) =>
  Object.keys(next).filter(key => key in previous && previous[key] !== "?" && previous[key] !== next[key])

export const Throughput = {
  mounted() {
    this.values = this.read()
  },
  updated() {
    const next = this.read()
    for (const key of changedKeys(this.values, next)) this.pulse(key)
    this.values = next
  },
  read() {
    const values = {}
    this.el.querySelectorAll("[data-key]").forEach(node => { values[node.dataset.key] = node.dataset.value })
    return values
  },
  pulse(key) {
    const node = Array.from(this.el.querySelectorAll("[data-key]")).find(n => n.dataset.key === key)
    if (!node) return
    node.classList.remove("is-changed")
    void node.offsetWidth
    node.classList.add("is-changed")
  },
}
