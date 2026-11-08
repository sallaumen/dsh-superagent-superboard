// LiveView owns the URL via push_patch. Native dialogs supply focus trapping and inert background.
export const BoardPanels = {
  mounted() {
    this.onTrigger = event => {
      const trigger = event.target.closest('[data-panel-trigger]')
      if (!trigger) return
      this.opener = trigger
      this.openerId = trigger.id
      this.openerMenuId = trigger.closest('[data-board-menu]')?.id
      this.pendingEntry = true
    }
    this.onPanelIntent = () => { this.pendingEntry = true }
    this.onNavigate = () => {
      const hasPanel = new URL(location.href).searchParams.has('panel')
      if (this.pendingEntry && hasPanel) {
        history.replaceState({...history.state, boardPanelFrom: this.el.dataset.baseUrl}, '', location.href)
      }
      this.el.querySelectorAll('[data-board-menu][open]').forEach(menu => { menu.open = false })
      if (!hasPanel && this.openerId) this.scheduleFocusRestore()
      this.pendingEntry = false
    }
    this.onCancel = event => {
      if (!event.target.matches('.board-dialog')) return
      event.preventDefault()
      this.pushEvent('close', {})
    }
    this.onKey = event => {
      if (event.key !== 'Escape' || event.defaultPrevented) return
      if (this.el.dataset.panel !== 'conversation') return
      if (this.el.querySelector('.board-dialog[open]')) return
      event.preventDefault()
      this.pushEvent('close', {})
    }
    this.el.addEventListener('click', this.onTrigger, true)
    window.addEventListener('board:panel-intent', this.onPanelIntent)
    this.el.addEventListener('cancel', this.onCancel, true)
    document.addEventListener('keydown', this.onKey)
    window.addEventListener('phx:navigate', this.onNavigate)
    this.handleEvent('panel_close', () => {
      if (history.state?.boardPanelFrom === this.el.dataset.baseUrl) history.back()
      else this.pushEvent('dismiss_panel', {}) // Direct URL: replace, never add an empty board entry.
    })
    this.sync()
  },
  updated() { this.sync() },
  sync() {
    const selected = this.el.dataset.panel
    const openingInspector = selected === 'conversation' && this.activePanel !== 'conversation'
    this.el.querySelectorAll('.board-dialog').forEach(dialog => {
      const wanted = dialog.id === `panel-${selected}`
      if (wanted && !dialog.open) {
        dialog.showModal()
        const initial = dialog.id === "panel-composer" ? dialog.querySelector("textarea") : dialog.querySelector("h2")
        initial?.focus({preventScroll: true})
      } else if (!wanted && dialog.open) {
        dialog.close()

      }
    })
    if (this.activePanel && !selected) {
      this.scheduleFocusRestore()
    }
    const hasDialog = [...this.el.querySelectorAll('.board-dialog')].some(dialog => dialog.open)
    this.activePanel = selected
    document.body.classList.toggle('board-panel-open', hasDialog)
    if (openingInspector) {
      this.el.querySelector('#conversation .ab-insp__bar button')?.focus({preventScroll: true})
    }
    this.syncInert()
    window.dispatchEvent(new Event('board:voice-context'))
  },
  // The phone's inspector covers the board like a dialog; keep the board
  // behind it out of the tab order and the accessibility tree.
  syncInert() {
    const inspector = document.querySelector('#conversation')
    const work = document.querySelector('#board-work')
    if (!work) return
    const overlay = inspector && getComputedStyle(inspector).position === 'absolute'
    if (overlay) work.setAttribute('inert', '')
    else work.removeAttribute('inert')
  },
  scheduleFocusRestore() {
    cancelAnimationFrame(this.restoreFrame)
    this.restoreFrame = requestAnimationFrame(() => {
      const opener = this.opener?.isConnected ? this.opener : document.getElementById(this.openerId)
      const menuSummary = this.openerMenuId && document.getElementById(this.openerMenuId)?.querySelector('summary')
      const focusTarget = menuSummary || opener || this.el.querySelector('#board-tools button')
      if (!this.el.dataset.panel) {
        focusTarget?.focus({preventScroll: true})
        this.opener = null
        this.openerId = null
        this.openerMenuId = null
      }
    })
  },
  disconnected() { this.el.dataset.socket = 'reconnecting' },
  reconnected() { this.el.dataset.socket = 'live'; this.sync() },
  destroyed() {
    cancelAnimationFrame(this.restoreFrame)
    this.el.removeEventListener('click', this.onTrigger, true)
    window.removeEventListener('board:panel-intent', this.onPanelIntent)
    this.el.removeEventListener('cancel', this.onCancel, true)
    document.removeEventListener('keydown', this.onKey)
    window.removeEventListener('phx:navigate', this.onNavigate)
    document.body.classList.remove('board-panel-open')
  },
}
