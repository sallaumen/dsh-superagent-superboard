// Elapsed time advances locally. No browser polling or claim about runner health.
export const ageLabel = (at, now, sync = false) => {
  if (!Number.isFinite(at) || !Number.isFinite(now)) return {text: "unknown", state: "unknown"}
  const seconds = Math.floor((now - at) / 1000)
  if (seconds < -60) return {text: "unknown (timestamp is ahead)", state: "unknown"}
  const minutes = Math.floor(Math.max(0, seconds) / 60)
  const elapsed = minutes < 1 ? "just now" : minutes < 60 ? `${minutes}m ago` :
    minutes < 1440 ? `${Math.floor(minutes / 60)}h ${minutes % 60}m ago` : `${Math.floor(minutes / 1440)}d ago`
  const state = !sync ? "record" : minutes >= 5 ? "stale" : minutes >= 2 ? "delayed" : "recent"
  const suffix = state === "stale" ? " · stale — showing saved data" : state === "delayed" ? " · update delayed" : ""
  return {text: elapsed + suffix, state}
}

export const DataAge = {
  mounted() {
    this.resetClock()
    this.timer = setInterval(() => this.paint(), 15000)
    this.onVisible = () => this.paint()
    document.addEventListener("visibilitychange", this.onVisible)
  },
  updated() { this.resetClock() },
  resetClock() {
    this.serverNow = Date.parse(this.el.dataset.now)
    this.started = performance.now()
    this.paint()
  },
  paint() {
    const result = ageLabel(Date.parse(this.el.dataset.at), this.serverNow + performance.now() - this.started, this.el.dataset.sync === "true")
    const text = `${this.el.dataset.label}: ${result.text}`
    if (this.el.textContent !== text) this.el.textContent = text
    this.el.dataset.ageState = result.state
  },
  destroyed() {
    clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.onVisible)
  },
}
