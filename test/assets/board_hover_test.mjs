import {readFileSync} from 'node:fs'
import assert from 'node:assert/strict'
import test from 'node:test'
const source = readFileSync(new URL('../../assets/js/board_hover.js', import.meta.url), 'utf8')
const {taskOf, relatedSelector} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('a lane card and a tree node stand for their task; anything else for none', () => {
  assert.equal(taskOf({dataset: {task: '57022'}, id: 'task-57022'}), '57022')
  assert.equal(taskOf({dataset: {}, id: 'objective-tree-node-41'}), '41')
  assert.equal(taskOf({dataset: {}, id: 'log-day-2026-11-12'}), null)
  assert.equal(taskOf({dataset: {task: '1"],[x'}, id: ''}), null)
  assert.equal(taskOf(null), null)
})
test('the same task is found by its data-task and its tree node', () => {
  assert.equal(relatedSelector('7'), '[data-task="7"], #objective-tree-node-7')
})
