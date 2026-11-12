import {readFileSync} from 'node:fs'
import assert from 'node:assert/strict'
import test from 'node:test'
const source = readFileSync(new URL('../../assets/js/hooks/costs_motion.js', import.meta.url), 'utf8')
const {sweepDelay, meterFrom, duration} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('a window of any size sweeps within the same time, first bar at once', () => {
  assert.equal(sweepDelay(0, 7), 0)
  assert.equal(sweepDelay(6, 7), 240)
  assert.equal(sweepDelay(89, 90), 240)
  assert.equal(sweepDelay(0, 1), 0)
})
test('a meter grows from its old width; a new or empty one from nothing', () => {
  assert.equal(meterFrom(25, 50), 0.5)
  assert.equal(meterFrom(50, 50), 1)
  assert.equal(meterFrom(10, 0), 0)
  assert.equal(meterFrom(100, 5), 4) // a meter that shrank a lot starts at most 4x wider
})
test('a taller bar takes a little longer, inside the clamp', () => {
  assert.ok(duration(148) > duration(20))
  assert.ok(duration(148) <= 520)
})
