import {readFileSync} from 'node:fs'
import assert from 'node:assert/strict'
import test from 'node:test'
const source = readFileSync(new URL('../../assets/js/hooks/board_motion.js', import.meta.url), 'utf8')
const {plan, newDots, duration, react} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

const at = (lane, index, x, y) => ({lane, index, x, y})

test('a patch that moved no card between lanes or in order animates nothing', () => {
  // The inspector opened: every card shifted left, none changed place.
  assert.equal(plan({a: at('sec-queue', 0, 400, 10)}, {a: at('sec-queue', 0, 200, 10)}), null)
})
test('a card that changed lane travels from where it was, and the lane is marked', () => {
  const change = plan({a: at('sec-queue', 0, 600, 300), b: at('sec-queue', 1, 600, 360)},
                      {a: at('sec-now', 0, 0, 100), b: at('sec-queue', 0, 600, 300)})
  assert.deepEqual(change.moves, [{key: 'a', dx: 600, dy: 200, lane: true}, {key: 'b', dx: 0, dy: 60, lane: false}])
  assert.deepEqual(change.enters, [])
  assert.deepEqual(change.exits, [])
})
test('arrivals and departures are listed; a reload of many is a cut', () => {
  const change = plan({a: at('sec-queue', 0, 0, 0)}, {b: at('sec-queue', 0, 0, 0)})
  assert.deepEqual([change.enters, change.exits], [['b'], ['a']])
  const many = Object.fromEntries(Array.from({length: 13}, (_, i) => [`t${i}`, at('sec-queue', i, 0, i)]))
  assert.equal(plan({}, many), null)
})
test('only the dots past a day\'s old count are new; a new day is not a merge', () => {
  assert.deepEqual(newDots({d1: 2, d2: 0}, {d1: 3, d2: 0, d3: 1}), [{day: 'd1', from: 2, to: 3}])
  assert.deepEqual(newDots({d1: 3}, {d1: 3}), [])
})
test('duration grows with distance and weight inside the clamp; reactions are uneven', () => {
  assert.equal(duration(0), 70)
  assert.ok(duration(400) > duration(100))
  assert.ok(duration(400, 1.3) > duration(400))
  assert.equal(duration(100000), 520)
  assert.deepEqual([0, 1, 2, 3].map(react), [0, 40, 90, 150])
})
