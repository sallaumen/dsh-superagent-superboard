import assert from 'node:assert/strict'
import test from 'node:test'
import {readFileSync} from 'node:fs'
const source = readFileSync(new URL('../../assets/js/hooks/settings_notice.js', import.meta.url), 'utf8')
const {SettingsNotice} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('a new message gets its own three seconds; a board refresh does not extend them', t => {
  t.mock.timers.enable({apis: ['setTimeout']})
  let dismissals = 0
  const el = Object.assign(new EventTarget(), {
    textContent: 'First message',
    querySelector: () => ({click: () => dismissals++}),
  })
  const notice = {...SettingsNotice, el}
  notice.mounted()
  t.mock.timers.tick(2500)
  el.textContent = 'Next message'
  notice.updated()
  t.mock.timers.tick(2500)
  notice.updated()
  assert.equal(dismissals, 0)
  t.mock.timers.tick(500)
  assert.equal(dismissals, 1)

  el.textContent = 'Closing the dialog'
  notice.updated()
  notice.destroyed()
  t.mock.timers.tick(3000)
  assert.equal(dismissals, 1)
})
