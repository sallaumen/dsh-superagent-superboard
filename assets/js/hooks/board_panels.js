// LiveView owns the URL via push_patch. Native dialogs supply focus trapping and inert background.
export const BoardPanels = {
  mounted() {
    this.onTrigger = event => {
      const trigger = event.target.closest('[data-panel-trigger]')
      if (!trigger) return
      this.opener = trigger
      this.openerId = trigger.id
      this.pendingEntry = true
    }
    this.onNavigate = () => {
      if (this.pendingEntry && new URL(location.href).searchParams.has('panel')) {
        history.replaceState({...history.state, boardPanelFrom: this.el.dataset.baseUrl}, '', location.href)
        this.pendingEntry = false
      }
    }
    this.onCancel = event => {
      if (!event.target.matches('.board-dialog')) return
      event.preventDefault()
      this.pushEvent('close', {})
    }
    this.el.addEventListener('click', this.onTrigger, true)
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
      this.restoreFrame = requestAnimationFrame(() => {
        const opener = this.opener?.isConnected ? this.opener : document.getElementById(this.openerId)
        if (!this.el.dataset.panel) (opener || this.el.querySelector('#board-tools button'))?.focus({preventScroll: true})
      })
    }
    this.activePanel = selected
    document.body.classList.toggle('board-panel-open', Boolean(selected))
  },
  disconnected() { this.el.dataset.socket = 'reconnecting' },
  reconnected() { this.el.dataset.socket = 'live'; this.sync() },
  destroyed() {
    cancelAnimationFrame(this.restoreFrame)
    this.el.removeEventListener('click', this.onTrigger, true)
    this.el.removeEventListener('cancel', this.onCancel, true)
    window.removeEventListener('phx:navigate', this.onNavigate)
    document.body.classList.remove('board-panel-open')
  },
}
