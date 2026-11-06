// The board's clocks run only while the data is live. A frozen board must not
// look like it is still counting: the age and the elapsed time are evidence.
export const BoardClock = {
  mounted() {
    this.restart()
    this.timer = setInterval(() => this.tick(), 1000)
  },
  updated() {
    // A server render resets the base values; keep the clock honest.
    this.restart()
    this.tick()
  },
  restart() {
    this.startedAt = Date.now()
  },
  tick() {
    const page = document.querySelector("#board-page")
    if (!page || page.dataset.connection === "down" || page.dataset.sync !== "live") return

    const delta = (Date.now() - this.startedAt) / 1000

    page.querySelectorAll("[data-tick]").forEach(node => {
      const base = Number(node.dataset.tick)
      if (Number.isFinite(base)) node.textContent = duration(base + delta)
    })

    page.querySelectorAll("[data-age]").forEach(node => {
      const base = Number(node.dataset.age)
      if (Number.isFinite(base)) node.textContent = ago(base + delta)
    })
  },
  destroyed() {
    clearInterval(this.timer)
  },
}

function duration(sec) {
  sec = Math.max(0, Math.floor(sec))
  const h = Math.floor(sec / 3600)
  const m = Math.floor((sec % 3600) / 60)
  const s = sec % 60
  if (h) return `${h} h ${String(m).padStart(2, "0")} min`
  return `${m}:${String(s).padStart(2, "0")}`
}

function ago(sec) {
  sec = Math.max(0, Math.floor(sec))
  if (sec < 60) return `há ${sec} s`
  if (sec < 3600) return `há ${Math.floor(sec / 60)} min`
  if (sec < 86400) return `há ${Math.floor(sec / 3600)} h`
  return `há ${Math.floor(sec / 86400)} d`
}
