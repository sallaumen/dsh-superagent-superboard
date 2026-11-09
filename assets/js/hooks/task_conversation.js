// The task conversation follows new turns only while the reader is at the end.
// A local submit always brings its own message into view; sync updates never
// replay the entry motion.
const BOTTOM_PIN = 64

export const TaskConversation = {
  mounted() {
    this.taskId = this.el.dataset.taskId
    this.body = null
    this.pinned = true
    this.submitted = false
    this.onScroll = () => {
      if (this.body) this.pinned = this.body.scrollHeight - this.body.scrollTop - this.body.clientHeight < BOTTOM_PIN
    }
    this.onKeyDown = event => {
      if (event.target.id !== "ask-body" || event.key !== "Enter" || event.shiftKey || event.altKey || event.isComposing) return
      if (event.target.disabled || !event.target.value.trim()) return
      event.preventDefault()
      event.target.form?.requestSubmit()
    }
    this.onSubmit = event => {
      if (event.target.id !== "ask-agent") return
      if (!event.target.querySelector("#ask-body")?.value.trim()) return
      this.submitted = true
      this.pinned = true
    }
    this.el.addEventListener("keydown", this.onKeyDown)
    this.el.addEventListener("submit", this.onSubmit, true)
    this.handleEvent("inspector:message-sent", ({task_id: taskId}) => {
      if (String(taskId) === this.taskId) this.scrollToEnd()
    })
    this.handleEvent("inspector:message-failed", ({task_id: taskId}) => {
      if (String(taskId) !== this.taskId) return
      this.submitted = false
      requestAnimationFrame(() => this.el.querySelector("#ask-body")?.focus())
    })
    this.syncBody()
    this.lastMessages = this.messages()
    this.scrollToEnd()
  },

  updated() {
    const taskChanged = this.taskId !== this.el.dataset.taskId
    if (taskChanged) {
      this.taskId = this.el.dataset.taskId
      this.pinned = true
      this.submitted = false
    }
    this.syncBody()
    const messages = this.messages()
    const changed = messages.map(message => `${message.id}:${message.sending}`).join("|") !==
      this.lastMessages.map(message => `${message.id}:${message.sending}`).join("|")

    if (this.submitted) {
      const newOwnMessage = [...this.el.querySelectorAll('.ab-conversation .ab-msg--you[data-message-id]')]
        .find(message => !this.lastMessages.some(previous => previous.id === message.dataset.messageId))
      if (newOwnMessage) {
        newOwnMessage.classList.add("is-entering")
        clearTimeout(this.entryTimer)
        this.entryTimer = setTimeout(() => newOwnMessage.classList.remove("is-entering"), 250)
        this.submitted = false
      }
    }
    this.lastMessages = messages
    if (taskChanged || (changed && this.pinned)) this.scrollToEnd()
  },

  messages() {
    return [...this.el.querySelectorAll('.ab-conversation [data-message-id]')]
      .map(message => ({id: message.dataset.messageId, sending: message.dataset.messageSending || ""}))
  },

  syncBody() {
    const body = this.el.querySelector("#inspector-panel-conversa")
    if (body === this.body) return
    this.body?.removeEventListener("scroll", this.onScroll)
    this.body = body
    this.body?.addEventListener("scroll", this.onScroll, {passive: true})
  },

  scrollToEnd() {
    requestAnimationFrame(() => {
      if (this.body) this.body.scrollTop = this.body.scrollHeight
    })
  },

  destroyed() {
    clearTimeout(this.entryTimer)
    this.body?.removeEventListener("scroll", this.onScroll)
    this.el.removeEventListener("keydown", this.onKeyDown)
    this.el.removeEventListener("submit", this.onSubmit, true)
  },
}
