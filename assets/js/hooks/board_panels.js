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
        this.el.querySelectorAll('[data-board-menu][open]').forEach(menu => { menu.open = false })
      }
      if (!hasPanel && this.openerId) this.scheduleFocusRestore()
      this.pendingEntry = false
    }
    this.onCancel = event => {
      if (!event.target.matches('.board-dialog')) return
      event.preventDefault()
      this.pushEvent('close', {})
    }
    this.el.addEventListener('click', this.onTrigger, true)
    window.addEventListener('board:panel-intent', this.onPanelIntent)
    this.el.addEventListener('cancel', this.onCancel, true)
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
    this.el.querySelectorAll('.board-dialog').forEach(dialog => {
      const wanted = dialog.id === `panel-${selected}`
      if (wanted && !dialog.open) {
        dialog.showModal()
        dialog.querySelector('h2').focus({preventScroll: true})
      } else if (!wanted && dialog.open) {
        dialog.close()

      }
    })
    if (this.activePanel && !selected) {
      this.scheduleFocusRestore()
    }
    this.activePanel = selected
    document.body.classList.toggle('board-panel-open', Boolean(selected))
    window.dispatchEvent(new Event('board:voice-context'))
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
    window.removeEventListener('phx:navigate', this.onNavigate)
    document.body.classList.remove('board-panel-open')
  },
}
