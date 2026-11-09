// The logs sheet: a bottom sheet the owner can drag, expand or collapse.
// The chosen height lives in this module for as long as the page is open; a
// reload starts at the CSS default. LiveView owns the data and the timer.
const MIN_HEIGHT = 180
const MAX_RATIO = 0.84
const BOTTOM_PIN = 32

let rememberedHeight = null

export const LogsSheet = {
  mounted() {
    this.dialog = this.el
    this.handle = this.el.querySelector('[data-log-drag]')
    this.body = this.el.querySelector('#logs-body')
    this.pinned = true

    this.onPointerDown = event => {
      if (!this.handle || event.button !== 0) return
      event.preventDefault()
      this.startY = event.clientY
      this.startHeight = this.height()
      this.dragging = true
      this.handle.setPointerCapture?.(event.pointerId)
      document.body.classList.add('ab-logs-resizing')
    }
    this.onPointerMove = event => {
      if (!this.dragging) return
      event.preventDefault()
      this.setHeight(this.startHeight + (this.startY - event.clientY))
    }
    this.onPointerUp = event => {
      if (!this.dragging) return
      this.dragging = false
      if (this.handle.hasPointerCapture?.(event.pointerId)) {
        this.handle.releasePointerCapture(event.pointerId)
      }
      document.body.classList.remove('ab-logs-resizing')
      this.rememberHeight()
    }
    this.onKeyDown = event => {
      if (event.target !== this.handle) return
      const step = event.shiftKey ? 64 : 16
      const next = {
        ArrowUp: this.height() + step,
        ArrowDown: this.height() - step,
        Home: MIN_HEIGHT,
        End: this.max(),
      }[event.key]
      if (next === undefined) return
      event.preventDefault()
      this.setHeight(next)
      this.rememberHeight()
    }
    this.onClick = event => {
      const button = event.target.closest?.('[data-log-size]')
      if (!button) return
      this.setHeight(button.dataset.logSize === 'max' ? this.max() : MIN_HEIGHT)
      this.rememberHeight()
    }
    this.onToggle = () => {
      if (!this.dialog.open) return
      requestAnimationFrame(() => {
        this.applyRemembered()
        this.scrollToEnd(true)
      })
    }
    this.onWindowResize = () => { if (this.dialog.open) this.setHeight(this.height()) }
    this.onScroll = () => { this.pinned = this.atBottom() }

    this.handle?.addEventListener('pointerdown', this.onPointerDown)
    this.handle?.addEventListener('pointermove', this.onPointerMove)
    this.handle?.addEventListener('pointerup', this.onPointerUp)
    this.handle?.addEventListener('pointercancel', this.onPointerUp)
    this.handle?.addEventListener('keydown', this.onKeyDown)
    this.el.addEventListener('click', this.onClick)
    this.el.addEventListener('toggle', this.onToggle)
    window.addEventListener('resize', this.onWindowResize)
    this.body?.addEventListener('scroll', this.onScroll, {passive: true})

    this.handle?.setAttribute('aria-valuenow', Math.round(this.height()))
    this.applyRemembered()
    this.scrollToEnd(true)
  },

  updated() {
    this.applyRemembered()
    if (this.pinned) this.scrollToEnd()
  },

  applyRemembered() {
    if (rememberedHeight) this.writeHeight(rememberedHeight)
  },

  rememberHeight() {
    rememberedHeight = this.height()
  },

  height() {
    return parseFloat(getComputedStyle(this.dialog).height) || MIN_HEIGHT
  },

  max() {
    return Math.max(MIN_HEIGHT, Math.min(Math.round(window.innerHeight * MAX_RATIO), window.innerHeight - 48))
  },

  setHeight(value) {
    const next = Math.max(MIN_HEIGHT, Math.min(Math.round(value), this.max()))
    this.writeHeight(next)
    if (this.pinned) this.scrollToEnd()
  },

  writeHeight(value) {
    this.dialog.style.setProperty('--ab-logs-height', `${value}px`)
    this.handle?.setAttribute('aria-valuenow', value)
    this.handle?.setAttribute('aria-valuemax', this.max())
  },

  atBottom() {
    if (!this.body) return true
    return this.body.scrollHeight - this.body.scrollTop - this.body.clientHeight < BOTTOM_PIN
  },

  scrollToEnd(force = false) {
    if (!this.body || (!force && !this.pinned)) return
    this.body.scrollTop = this.body.scrollHeight
  },

  destroyed() {
    this.handle?.removeEventListener('pointerdown', this.onPointerDown)
    this.handle?.removeEventListener('pointermove', this.onPointerMove)
    this.handle?.removeEventListener('pointerup', this.onPointerUp)
    this.handle?.removeEventListener('pointercancel', this.onPointerUp)
    this.handle?.removeEventListener('keydown', this.onKeyDown)
    this.el.removeEventListener('click', this.onClick)
    this.el.removeEventListener('toggle', this.onToggle)
    window.removeEventListener('resize', this.onWindowResize)
    this.body?.removeEventListener('scroll', this.onScroll)
    document.body.classList.remove('ab-logs-resizing')
  },
}
