// Clear the LiveView flash itself, including its copy behind the modal.
export const SettingsNotice = {
  mounted() {
    this.schedule = () => {
      clearTimeout(this.timer)
      if (!this.hovered && !this.focused) {
        this.timer = setTimeout(() => this.el.querySelector('button').click(), 3000)
      }
    }
    this.onPointer = event => {
      if (event.pointerType === 'touch') return
      this.hovered = event.type === 'pointerenter'
      this.schedule()
    }
    this.onFocus = event => {
      this.focused = event.type === 'focusin' || this.el.contains(event.relatedTarget)
      this.schedule()
    }
    this.el.addEventListener('pointerenter', this.onPointer)
    this.el.addEventListener('pointerleave', this.onPointer)
    this.el.addEventListener('focusin', this.onFocus)
    this.el.addEventListener('focusout', this.onFocus)
    this.message = this.el.textContent
    this.schedule()
  },
  updated() {
    if (this.message !== this.el.textContent) {
      this.message = this.el.textContent
      this.schedule()
    }
  },
  destroyed() {
    clearTimeout(this.timer)
    this.el.removeEventListener('pointerenter', this.onPointer)
    this.el.removeEventListener('pointerleave', this.onPointer)
    this.el.removeEventListener('focusin', this.onFocus)
    this.el.removeEventListener('focusout', this.onFocus)
  },
}
