# agent-board

The board for the agent's work, in Elixir: **Ecto** for the data, **Oban** for
the durable sync, **LiveView** for the real-time UI and **Req** for GitHub.

## Why Elixir

- The **sync is a durable job**, not a hand-rolled loop: Oban retries it, the
  supervisor restarts it, and the dashboard shows it. Cron runs it every minute.
- The **board is real-time**: a `Phoenix.PubSub` broadcast updates every connected
  LiveView when the sync or an action changes a task — no browser polling.
- The **data is migrations**, not a SQL file applied on boot: Ecto owns the
  schema, the changesets and the history.
- **One language** with the game and the rest of the system.

## Run it

```sh
mix setup            # deps, database, assets
mix phx.server       # http://127.0.0.1:4002
```

The dev database is on the local Postgres at `127.0.0.1:5434`.

## What it does

- **Syncs** the tracked repositories' issues and pull requests (the Oban
  `Sync.Worker`, one cron run per minute).
- **Syncs reviews and CI** per pull request: `review_state` (approved, changes
  requested, pending) and `checks_state` (success, failure, pending), with the
  failing check named.
- **Reads the agent's tickets** (read-only, from the mounted sqlite) and overlays
  the live state on the issue: running, ready, blocked — while the issue is open.
- **Creates a task** by opening a GitHub issue that mentions the agent.
- **Stops** (the flag plus closing the issue) and **archives** a task.
- **Speaks**: "Speak status" reads the board out loud (the Web Speech API);
  "Dictate task" turns a sentence into a task title.

## What it costs

- **The sync** reads the 100 most recently updated issues and pull requests per
  repository (the `recent()` window), plus each pull request's reviews and check
  runs, plus the comments of up to 10 active tasks. At the 1 min cron that is
  real API traffic. On `o_colmex` (1,100+ pull requests) the **first** sync is
  the slow one; later runs only refresh the recent window.
- **The 10s poller does not touch GitHub**: it reads the agent's sqlite and
  only broadcasts when the ticket hash changed.

## The gates

```sh
mix gate   # check-only: compile warnings + format + credo + tests (CI runs this)
mix precommit  # same gates, formatting fixed in place (for developers)
scripts/ci-local.sh all   # pre-flight: backend + frontend + library pipelines
```

Which script to run when — backend, frontend, library or the mixed release
path — is in [PIPELINES.md](PIPELINES.md).

## The tests

59 tests, each layer covered: the state mapping (the ticket overlay, the review
and check rollups), the voice summary, the context, the LiveView (the
columns, the empty state, the voice events, the PubSub broadcast).

## The limits

- **Stop** is the board's flag plus closing the issue. A worker already running
  finishes its current ticket: the Super-Agent API has no cancel endpoint.
- The board **reads** the agent's state; it never writes to it.
- The voice uses the browser's speech APIs; no server-side TTS.

## The capabilities library

Reusable development workflows (architecture, product, UI/UX, testing, code
review, integrations and operations) live in
[`capabilities/`](capabilities/CATALOGO.md), adapted from the
`biblioteca-prompts-desenvolvimento` package. The catalog is the entry point;
the source-to-destination map and decisions are in
[`capabilities/INCORPORACAO.md`](capabilities/INCORPORACAO.md).
