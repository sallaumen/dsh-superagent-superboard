import {readFileSync} from 'node:fs'
import assert from 'node:assert/strict'
import test from 'node:test'
const source = readFileSync(new URL('../../assets/js/hooks/board_keyboard.js', import.meta.url), 'utf8')
const {startVoiceWhenComposerOpens} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

const tick = () => new Promise(resolve => setTimeout(resolve, 20))

const page = () => {
  const win = new EventTarget()
  const doc = {composerOpen: false, querySelector: () => (doc.composerOpen ? {} : null)}
  let starts = 0
  win.addEventListener('board:voice-start', () => starts++)
  return {win, doc, starts: () => starts}
}

test('the voice starts on the panel update that opens the composer, once', () => {
  const {win, doc, starts} = page()
  startVoiceWhenComposerOpens(win, doc, 1000)

  win.dispatchEvent(new Event('board:voice-context'))
  assert.equal(starts(), 0, 'an unrelated panel update does not start the voice')

  doc.composerOpen = true
  win.dispatchEvent(new Event('board:voice-context'))
  win.dispatchEvent(new Event('board:voice-context'))
  assert.equal(starts(), 1)
})

test('a composer that never opens starts nothing', async () => {
  const {win, doc, starts} = page()
  startVoiceWhenComposerOpens(win, doc, 5)

  await tick()
  doc.composerOpen = true
  win.dispatchEvent(new Event('board:voice-context'))
  assert.equal(starts(), 0)
})
