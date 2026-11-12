// What the pointer is on, and where else the same task is. A card under a
// mouse gets a soft light that follows the pointer (--mx, --my), in the colour
// of who acts next (CSS --role). Every other place the same task shows (its
// row in a lane, its node in the objective tree, its "taking long" notice) is
// marked `is-related`, so the eye finds it. Pointer events only: no timer, no
// fetch; touch and pen get the plain hover; reduced motion keeps the light
// centred instead of following.

const CARDS = ".ab-run, .ab-need, .ab-row, .ab-pr, .ab-tree__node"

// The task a card stands for: the lanes carry data-task, the tree its node id.
// Task ids are integers; anything else is not a task.
export const taskOf = el => {
  const id = el?.dataset?.task || el?.id?.match(/^objective-tree-node-(\d+)$/)?.[1]
  return /^\d+$/.test(id ?? "") ? id : null
}

// Every other element on the page for the same task.
export const relatedSelector = task => `[data-task="${task}"], #objective-tree-node-${task}`

export const mountBoardHover = (root = document) => {
  let lit = null
  let frame = 0
  let point = null
  const quiet = window.matchMedia("(prefers-reduced-motion: reduce)")

  const clearRelated = () => root.querySelectorAll(".is-related").forEach(el => el.classList.remove("is-related"))

  root.addEventListener("pointerover", event => {
    if (event.pointerType !== "mouse") return
    const card = event.target.closest?.(CARDS)
    if (!card || card === lit) return
    lit = card
    clearRelated()
    const task = taskOf(card)
    if (task) root.querySelectorAll(relatedSelector(task)).forEach(el => el !== card && el.classList.add("is-related"))
  })

  root.addEventListener("pointerout", event => {
    if (!lit || lit.contains(event.relatedTarget)) return
    lit.style.removeProperty("--mx")
    lit.style.removeProperty("--my")
    lit = null
    clearRelated()
  })

  // One write per frame, only for the card under the pointer.
  root.addEventListener("pointermove", event => {
    if (!lit || event.pointerType !== "mouse" || quiet.matches) return
    point = event
    if (frame) return
    frame = requestAnimationFrame(() => {
      frame = 0
      if (!lit || !point) return
      const box = lit.getBoundingClientRect()
      lit.style.setProperty("--mx", `${Math.round(point.clientX - box.left)}px`)
      lit.style.setProperty("--my", `${Math.round(point.clientY - box.top)}px`)
    })
  })
}
