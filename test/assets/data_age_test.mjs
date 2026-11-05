import {readFileSync} from 'node:fs'
import assert from 'node:assert/strict'
import test from 'node:test'
const source = readFileSync(new URL('../../assets/js/hooks/data_age.js', import.meta.url), 'utf8')
const {ageLabel} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('completed sync ages through recent, delayed and stale without a new response', () => {
  assert.equal(ageLabel(0, 119000, true).state, 'recent')
  assert.equal(ageLabel(0, 120000, true).state, 'delayed')
  assert.equal(ageLabel(0, 299000, true).state, 'delayed')
  assert.equal(ageLabel(0, 300000, true).state, 'stale')
  assert.match(ageLabel(0, 300000, true).text, /showing saved data/)
})
test('old activity is an age, not evidence of a broken sync', () => {
  assert.deepEqual(ageLabel(0, 3600000), {text: '1h 0m ago', state: 'record'})
})
test('missing and future timestamps never imply fresh data', () => {
  assert.equal(ageLabel(NaN, 0, true).state, 'unknown')
  assert.equal(ageLabel(120000, 0, true).state, 'unknown')
})
