import {readFileSync} from 'node:fs'
import assert from 'node:assert/strict'
import test from 'node:test'
const source = readFileSync(new URL('../../assets/js/hooks/throughput.js', import.meta.url), 'utf8')
const {changedKeys} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('only a value that differs from the last render pulses', () => {
  assert.deepEqual(changedKeys({done: '2', merged: '1'}, {done: '3', merged: '1'}), ['done'])
})
test('a broadcast with the same values pulses nothing', () => {
  assert.deepEqual(changedKeys({done: '2'}, {done: '2'}), [])
})
test('a key seen for the first time is a mount, not a change', () => {
  assert.deepEqual(changedKeys({}, {done: '2'}), [])
})
