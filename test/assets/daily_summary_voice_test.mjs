import {readFileSync} from 'node:fs'
import assert from 'node:assert/strict'
import test from 'node:test'
const source = readFileSync(new URL('../../assets/js/hooks/daily_summary_voice.js', import.meta.url), 'utf8')
const {hasBeenActive, dismissing} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('a tab nobody touched never asks to speak the summary', () => {
  assert.equal(hasBeenActive(false), false)
  assert.equal(hasBeenActive(undefined), false)
})
test('a tab where the page saw a click or a key asks', () => {
  assert.equal(hasBeenActive(true), true)
})
test('the click that dismisses the summary is not a request to hear it', () => {
  assert.equal(dismissing({closest: sel => (sel === '[data-daily-dismiss]' ? {} : null)}), true)
  assert.equal(dismissing({closest: () => null}), false)
  assert.equal(dismissing(null), false)
})
