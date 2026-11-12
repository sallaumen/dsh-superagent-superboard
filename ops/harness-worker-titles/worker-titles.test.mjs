import test from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, realpathSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { DatabaseSync } from 'node:sqlite'
import { install, projectTitle, ticketReader } from './index.js'

test('session creation and cold listing from a second host agree, without losing personal titles', () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'superboard-session-')))
  try {
    const id = '0123456789abcdef0123456789abcdef', profile = join(root, 'state', 'superagent')
    mkdirSync(profile, {recursive:true})
    const header = {id:'worker-'+id, cwd:join(profile, 'work','hud-redesign-'+id.slice(0,12))}
    const ticket = {title:'Redesign do HUD', execution:{directory:header.cwd},channels:[{address:{url:'https://github.com/owner/arena-rogue/issues/224'}}]}
    const db = new DatabaseSync(join(profile,'orchestrator.sqlite'))
    try {
      db.exec('CREATE TABLE ticket (id TEXT PRIMARY KEY, value TEXT); CREATE TABLE kv (key TEXT PRIMARY KEY,value TEXT)')
      db.prepare('INSERT INTO ticket VALUES (?,?)').run(id, JSON.stringify(ticket))
    } finally { db.close() }
    const disposers = [], blank = () => undefined
    const host = {
      sessionProjectionCache:{cachedSnapshot:blank},
      sessionProjections:{snapshot:() => ({asOfSeq:12, values:{other:true,title:'Meu nome'}})},
      sessionTitle:{rename:(_s,t)=>t},effect:f=>disposers.push(f())
    }
    install(host, ticketReader(root))
    const title = host.sessionTitle.rename({header},ticket.title)
    assert.equal(title,'AR - Redesign do HUD')
    assert.equal(host.sessionTitle.rename({header},'Planejamento'), 'Planejamento')
    assert.deepEqual(host.sessionProjectionCache.cachedSnapshot(header), {asOfSeq:-1,values:{title}})
    assert.deepEqual(host.sessionProjections.snapshot({header}),{asOfSeq:12,values:{other:true,title:'Meu nome'}})
    for(const unrelated of [{...header,id:'normal'},{...header,cwd:join(root,'other')},{...header,cwd:header.cwd.replace('hud-redesign','another')}]) {
      assert.equal(host.sessionProjectionCache.cachedSnapshot(unrelated),undefined)
    }
    assert.equal(host.sessionProjectionCache.cachedSnapshot(header,new Set(['other'])),undefined)
    disposers.reverse().forEach(dispose=>dispose())
    assert.equal(host.sessionProjectionCache.cachedSnapshot,blank)
  } finally { rmSync(root,{recursive:true,force:true}) }
})
test('prefixes are bounded, stable and never leave an untitled task', () => {
  assert.equal(projectTitle('owner/o_colmex','Corrigir\nmenu'),'COL - Corrigir menu')
  assert.equal(projectTitle('dsh-superagent-superboard','SB - Corrigir menu'),'SB - Corrigir menu')
  assert.equal(projectTitle('ação','Untitled','ajustar-menu'),'ACA - ajustar menu')
  assert.equal(projectTitle('one-two-three-four','Criar perfil'),'OTT - Criar perfil')
})
