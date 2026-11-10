import {readFileSync} from 'node:fs'
import assert from 'node:assert/strict'
import test from 'node:test'
const source = readFileSync(new URL('../../assets/js/hooks/board_connection.js', import.meta.url), 'utf8')
const {holdsDraft, restartRequested} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('a tab with unsent text is not reloaded after a restart', () => {
  assert.equal(holdsDraft([]), false)
  assert.equal(holdsDraft([{value: ''}, {value: '  \n'}]), false)
  assert.equal(holdsDraft([{value: ''}, {value: 'fix the login'}]), true)
})

test('the update click still counts after a long compile, not forever', () => {
  assert.equal(restartRequested(0, 1000), false)
  assert.equal(restartRequested(1000, 1000 + 5 * 60 * 1000), true)
  assert.equal(restartRequested(1000, 1000 + 10 * 60 * 1000), false)
})
