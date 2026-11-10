import {readFileSync} from 'node:fs'
import assert from 'node:assert/strict'
import test from 'node:test'
const source = readFileSync(new URL('../../assets/js/hooks/image_viewer.js', import.meta.url), 'utf8')
const {ImageViewer} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

const node = () => ({attrs: {}, listeners: {}, dataset: {}, setAttribute(k, v) { this.attrs[k] = v },
  addEventListener(type, fn) { this.listeners[type] = fn }, removeEventListener() {}})
const viewer = () => {
  const parts = {'#image-viewer-name': node(), '[data-viewer-target]': node(), '[data-viewer-download]': node(), '[data-viewer-tab]': node()}
  return {...node(), parts, opened: 0, closed: 0, querySelector: selector => parts[selector],
    showModal() { this.opened += 1 }, close() { this.closed += 1 }}
}
const click = (link, keys = {}) => ({button: 0, prevented: false, target: {closest: () => link},
  preventDefault() { this.prevented = true }, ...keys})
const mount = dialog => {
  globalThis.document = {getElementById: () => dialog}
  const hook = {...ImageViewer, el: node()}
  hook.mounted()
  return hook.el.listeners.click
}
const link = {href: '/attachments/1/abc/tela.png', dataset: {viewerImage: 'tela.png'}}

test('a plain click opens the image in the viewer with its name and its download', () => {
  const dialog = viewer()
  const event = click(link)
  mount(dialog)(event)
  assert.equal(event.prevented, true)
  assert.equal(dialog.opened, 1)
  assert.equal(dialog.parts['[data-viewer-target]'].src, link.href)
  assert.equal(dialog.parts['#image-viewer-name'].textContent, 'tela.png')
  assert.equal(dialog.parts['[data-viewer-download]'].attrs.download, 'tela.png')
  assert.equal(dialog.parts['[data-viewer-tab]'].href, link.href)
})
test('a modified click and a link that is not an image stay links', () => {
  const dialog = viewer()
  const onClick = mount(dialog)
  for (const event of [click(link, {metaKey: true}), click(link, {button: 1}), click(null)]) {
    onClick(event)
    assert.equal(event.prevented, false)
  }
  assert.equal(dialog.opened, 0)
})
test('Escape closes the viewer and no key reaches the board behind it', () => {
  const dialog = viewer()
  mount(dialog)(click(link))
  const key = {key: 'Escape', stopped: false, stopPropagation() { this.stopped = true }, preventDefault() {}}
  dialog.listeners.keydown(key)
  assert.equal(key.stopped, true)
  assert.equal(dialog.closed, 1)
  const other = {key: 'j', stopped: false, stopPropagation() { this.stopped = true }, preventDefault() {}}
  dialog.listeners.keydown(other)
  assert.equal(other.stopped, true)
  assert.equal(dialog.closed, 1)
})
