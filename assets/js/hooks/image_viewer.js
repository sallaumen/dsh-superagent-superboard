// A message's image opens over the board instead of in another tab. The link
// stays a link: without this hook, or on a modified click, it opens as before.
const plainClick = event =>
  event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey

const prepare = dialog => {
  if (dialog.dataset.ready) return
  dialog.dataset.ready = "true"
  // The keys belong to the viewer while it is open: Escape closes it and
  // nothing reaches the board's own shortcuts behind it.
  dialog.addEventListener("keydown", event => {
    event.stopPropagation()
    if (event.key === "Escape") {
      event.preventDefault()
      dialog.close()
    }
  })
  dialog.addEventListener("click", event => {
    const outside = event.target === dialog || event.target.matches("[data-viewer-target]")
    if (outside || event.target.closest("[data-viewer-close]")) dialog.close()
  })
}

export const ImageViewer = {
  mounted() {
    this.onClick = event => {
      const link = event.target.closest("[data-viewer-image]")
      const dialog = document.getElementById("image-viewer")
      if (!link || !dialog || !plainClick(event)) return
      event.preventDefault()
      prepare(dialog)
      const name = link.dataset.viewerImage
      dialog.querySelector("#image-viewer-name").textContent = name
      const image = dialog.querySelector("[data-viewer-target]")
      image.src = link.href
      image.alt = name
      const download = dialog.querySelector("[data-viewer-download]")
      download.href = link.href
      download.setAttribute("download", name)
      dialog.querySelector("[data-viewer-tab]").href = link.href
      dialog.showModal()
    }
    this.el.addEventListener("click", this.onClick)
  },
  destroyed() {
    this.el.removeEventListener("click", this.onClick)
  },
}
