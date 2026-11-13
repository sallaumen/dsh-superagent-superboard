// DSH hosts have separate in-memory projection caches even when they share DSH_HOME.
import { DatabaseSync } from 'node:sqlite'
import { realpathSync } from 'node:fs'
import { homedir } from 'node:os'
import { basename, dirname, join, resolve } from 'node:path'

const worker = /^worker-([0-9a-f]{32})$/
const aliases = new Map([['arena-rogue', 'AR'], ['o_colmex', 'COL'], ['dsh-superagent-superboard', 'SB']])
const clean = value => String(value ?? '').replace(/[\p{Cc}\p{Cf}\s]+/gu, ' ').trim()

export function projectTitle(repo, title, fallback) {
  const name = (repo || '').split('/').at(-1).toLowerCase()
  const words = name.normalize('NFKD').replace(/\p{M}/gu, '').match(/[a-z]+/g) || []
  const code = aliases.get(name) || (words.length === 1 ? words[0].slice(0, 3) : words.slice(0, 3).map(w => w[0]).join('')).toUpperCase() || 'PRJ'
  const prefix = code + ' - '
  const text = clean(title)
  return text && !/^(untitled|sem t[ií]tulo)$/iu.test(text)
    ? (text.startsWith(prefix) ? text : prefix + text)
    : prefix + (clean(fallback).replace(/-/g, ' ') || 'Tarefa')
}

// Verify the worker identity, exact checkout and registered ticket. A browser-supplied
// path must never select an arbitrary database. Nothing is written to the agent.
export function ticketReader(root) {
  const state = resolve(realpathSync(root), 'state')
  const cache = new Map()
  return header => {
    const id = worker.exec(header?.id)?.[1]
    if (!id || typeof header.cwd !== 'string') return
    const cwd = header.cwd
    const profile = dirname(dirname(cwd))
    if (dirname(profile) !== state || basename(dirname(cwd)) !== 'work' || !basename(cwd).endsWith('-' + id.slice(0, 12))) return
    const found = cache.get(id)
    if (found?.cwd === cwd && found.until > Date.now()) return found.value
    let db
    try {
      db = new DatabaseSync(join(profile, 'orchestrator.sqlite'), {readOnly: true})
      const row = db.prepare(`SELECT value ->> '$.title' AS title,
        value ->> '$.channels[0].address.url' AS url FROM ticket
        WHERE id=? AND value ->> '$.execution.directory'=?`).get(id, cwd)
      if (!row) return
      let repo
      if (row.url) {
        try { const u = new URL(row.url); if (u.hostname === 'github.com') repo = u.pathname.split('/')[2] } catch {}
      }
      repo ||= db.prepare(`SELECT value ->> '$.settings.sources.github.config.repository' AS repo FROM kv
        WHERE key='settings-version:'||(SELECT value FROM kv WHERE key='settings-revision')`).get()?.repo
      const value = {title: row.title, label: projectTitle(repo, row.title, basename(cwd).slice(0,-13))}
      if (cache.size >= 512) cache.delete(cache.keys().next().value)
      cache.set(id, {cwd, value, until: Date.now() + 60000})
      return value
    } catch { return undefined } finally { db?.close() }
  }
}

// DSH's native list asks these services for either an attached or a cold row.
// Supply only the title; keep other projections and any owner's custom title.
export function apply(ctx) {
  ctx.inject(['sessionProjectionCache', 'sessionProjections', 'sessionTitle'], host => {
    install(host, ticketReader(process.env.DSH_HOME || join(homedir(), '.dsh')))
  })
}
export function install(ctx, read) {
  const wrap = (service, method, decorate) => {
    const target = service[Symbol.for('cordis.original')] || service
    const original = target[method]
    if (typeof original !== 'function') throw new Error('Incompatible Harness service: ' + method)
    const own = Object.getOwnPropertyDescriptor(target, method)
    const wrapped = function (...args) { return decorate(original.bind(this), ...args) }
    target[method] = wrapped
    ctx.effect(() => () => {
      if (target[method] !== wrapped) return
      if (own) Object.defineProperty(target, method, own)
      else delete target[method]
    })
  }
  const show = (block, header, keys) => {
    if (keys && !keys.has('title')) return block
    const row = read(header)
    const current = block?.values?.title
    if (!row || (current && current !== row.title && !/^(untitled|sem t[ií]tulo)$/iu.test(current))) return block
    return {...block, asOfSeq: block?.asOfSeq ?? -1, values: {...block?.values, title: row.label}}
  }
  wrap(ctx.sessionProjectionCache, 'cachedSnapshot', (next, header, keys) => show(next(header, keys), header, keys))
  wrap(ctx.sessionProjections, 'snapshot', (next, session, keys) => show(next(session, keys), session.header, keys))
  wrap(ctx.sessionTitle, 'rename', (next, session, title) => {
    const row = read(session.header)
    return next(session, row && title === row.title ? row.label : title)
  })
}
