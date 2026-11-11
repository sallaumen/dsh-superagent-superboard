import {readFileSync} from 'node:fs'
import assert from 'node:assert/strict'
import test from 'node:test'
const source = readFileSync(new URL('../../assets/js/hooks/value_change.js', import.meta.url), 'utf8')
const {changedKeys, rose, bucket} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('only a value that differs from the last render pulses', () => {
  assert.deepEqual(changedKeys({done: '2', merged: '1'}, {done: '3', merged: '1'}), ['done'])
})
test('a broadcast with the same values pulses nothing', () => {
  assert.deepEqual(changedKeys({done: '2'}, {done: '2'}), [])
})
test('a key seen for the first time is a mount, not a change', () => {
  assert.deepEqual(changedKeys({}, {done: '2'}), [])
})
test('the first answer after "?" is a reading, not a change', () => {
  assert.deepEqual(changedKeys({load: '?'}, {load: '2/3/0'}), [])
  assert.deepEqual(changedKeys({load: '2/3/0'}, {load: '?'}), ['load'])
})
test('a count that rose is up; one that fell or a non-number is not', () => {
  assert.equal(rose('2', '3'), true)
  assert.equal(rose('3', '2'), false)
  assert.equal(rose('?', '2'), false)
})
test('a bar is the start of its hour, so a later minute or a new count in the same hour is a growth', () => {
  assert.equal(bucket('19:00–19:48: 2'), bucket('19:00–19:55: 3'))
  assert.notEqual(bucket('19:00–19:59: 3'), bucket('20:00–20:01: 0'))
})
