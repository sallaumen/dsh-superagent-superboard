// Cards keep their identity when the board reloads: a task that moved from
// Fila to Agora travels there, the cards around it make room, a new one
// settles in its slot, one that left fades where it was, and a new merge
// adds its dot. The hook measures before and after LiveView's patch (FLIP);
// it never fetches and never runs on a patch that changed no card. A
// repository switch, a first render and a reconnect are cuts.

const CARDS = "#sec-now [id^='task-'], #sec-needs [id^='task-'], #sec-queue [id^='task-']"
const DAYS = "#sec-log .ab-day"
const BULK = 12 // more arrivals and departures than this reads as a new board, not a change

// Curves from the kit's MOTION.md; durations from distance and weight.
const TRAVEL_X = "cubic-bezier(0.1, 0.75, 0.15, 1)" // kit.land
const TRAVEL_Y = "cubic-bezier(0.05, 0.7, 0.1, 1)" // m3.emphasizedDecelerate
const ENTER_FADE = "cubic-bezier(0, 0, 0.38, 0.9)" // carbon.productive.entrance
const LEAVE = "cubic-bezier(0.55, 0, 0.9, 0.35)" // kit.leave
const ARRIVE = "cubic-bezier(0.34, 1.56, 0.64, 1)" // easings outBack, transforms only
const REACT = [0, 40, 90, 150, 220, 300]

export const duration = (px, weight = 1) => Math.round(Math.min(520, Math.max(70, (70 + 10 * Math.sqrt(px)) * weight)))
export const react = i => REACT[i] ?? 300 + (i - 5) * 70

// before/after: {key: {lane, index, x, y}}. Returns null when no card
// changed lane, order, arrived or left; otherwise what to animate.
export const plan = (before, after) => {
  const enters = Object.keys(after).filter(key => !(key in before))
  const exits = Object.keys(before).filter(key => !(key in after))
  const reordered = Object.keys(after).some(key =>
    key in before && (before[key].lane !== after[key].lane || before[key].index !== after[key].index))
  if (!enters.length && !exits.length && !reordered) return null
  if (enters.length + exits.length > BULK) return null
  const moves = Object.keys(after)
    .filter(key => key in before)
    .map(key => ({key, dx: before[key].x - after[key].x, dy: before[key].y - after[key].y,
                  lane: before[key].lane !== after[key].lane}))
    .filter(move => Math.abs(move.dx) >= 1 || Math.abs(move.dy) >= 1)
  return {moves, enters, exits}
}

// A day column's dots: the ones past the count it had are the new merges.
export const newDots = (before, after) =>
  Object.keys(after).filter(day => day in before && after[day] > before[day])
    .map(day => ({day, from: before[day], to: after[day]}))

const visible = rect => rect.width > 0 || rect.height > 0
const quiet = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches

export const BoardMotion = {
  mounted() {
    this.scope = this.el.dataset.motionScope
    this.running = new Set()
  },
  beforeUpdate() {
    this.cards = this.measure()
    this.dots = this.countDots()
  },
  destroyed() {
    this.stop()
  },
  updated() {
    const scope = this.el.dataset.motionScope
    const sameBoard = scope === this.scope
    this.scope = scope
    const cards = this.cards
    this.cards = null
    if (!cards || !sameBoard || quiet()) return

    this.stop()
    const after = this.measure()
    const change = plan(this.positions(cards), this.positions(after))
    const dots = newDots(this.dots, this.countDots())
    if (change) this.play(change, cards, after)
    dots.forEach(({day, from, to}, i) => this.pop(day, from, to, change ? 90 + react(i) : react(i)))
  },

  measure() {
    const cards = {}
    const index = {}
    this.el.querySelectorAll(CARDS).forEach(el => {
      const lane = el.closest("section").id
      const rect = el.getBoundingClientRect()
      if (!visible(rect) || el.id in cards) return
      index[lane] = (index[lane] ?? -1) + 1
      cards[el.id] = {el, lane, index: index[lane], rect}
    })
    return cards
  },
  positions(cards) {
    return Object.fromEntries(Object.entries(cards).map(([key, c]) =>
      [key, {lane: c.lane, index: c.index, x: c.rect.left, y: c.rect.top}]))
  },
  countDots() {
    const days = {}
    this.el.querySelectorAll(DAYS).forEach(day => { days[day.id] = day.querySelectorAll(".ab-day__dots i").length })
    return days
  },
  // A patch during a move: the card was measured where it was seen, so the
  // new move starts from there; the old one stops instead of queueing.
  stop() {
    this.running.forEach(animation => animation.cancel())
    this.running.clear()
  },

  play({moves, enters, exits}, before, after) {
    moves.forEach(({key, dx, dy, lane}) => {
      // A card that changed lane is the change; the others make room.
      const ms = duration(Math.hypot(dx, dy), lane ? 1.3 : 1)
      const el = after[key].el
      // The traveller passes over the cards making room, not under them.
      if (lane) el.classList.add("is-traveling")
      const x = this.run(el, [{transform: `translateX(${dx}px)`}, {transform: "none"}], ms, TRAVEL_X, 0)
      this.run(el, [{transform: `translateY(${dy}px)`}, {transform: "none"}], ms, TRAVEL_Y, 0, "add")
      const land = () => el.classList.remove("is-traveling")
      x.addEventListener("finish", land)
      x.addEventListener("cancel", land)
    })
    enters.forEach((key, i) => {
      const el = after[key].el
      const delay = 40 + react(i)
      this.run(el, [{opacity: 0}, {opacity: 1}], 140, ENTER_FADE, delay)
      this.run(el, [{transform: "translateY(6px)"}, {transform: "none"}], duration(6), TRAVEL_Y, delay)
    })
    exits.forEach(key => this.ghost(before[key]))
  },
  // The card already left the DOM; its old node fades where it stood, inert.
  ghost({el, rect}) {
    if (el.isConnected) return
    el.removeAttribute("id")
    el.setAttribute("aria-hidden", "true")
    el.inert = true
    Object.assign(el.style, {position: "fixed", left: `${rect.left}px`, top: `${rect.top}px`,
      width: `${rect.width}px`, height: `${rect.height}px`, margin: "0", pointerEvents: "none", zIndex: "1"})
    document.body.appendChild(el)
    const fade = this.run(el, [{opacity: 1, transform: "none"}, {opacity: 0, transform: "scale(0.98)"}],
      130, LEAVE, 0)
    fade.addEventListener("finish", () => el.remove())
    fade.addEventListener("cancel", () => el.remove())
  },
  pop(dayId, from, to, delay) {
    const dots = document.getElementById(dayId)?.querySelectorAll(".ab-day__dots i") ?? []
    Array.from(dots).slice(from, to).forEach((dot, i) =>
      this.run(dot, [{transform: "scale(0)"}, {transform: "none"}], 280, ARRIVE, delay + react(i)))
  },
  run(el, frames, ms, easing, delay, composite = "replace") {
    const animation = el.animate(frames, {duration: ms, easing, delay, composite, fill: "backwards"})
    this.running.add(animation)
    animation.addEventListener("finish", () => this.running.delete(animation))
    return animation
  },
}
