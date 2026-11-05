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
- **One language** across the board, the sync and the web layer.

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
- **Exposes a JSON API** under `/api` — the board, the repositories and the
  task actions; documented in [docs/api.md](docs/api.md).

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
mix gate   # check-only: unused deps + compile warnings + format + credo + tests
mix precommit  # same gates, formatting fixed in place (for developers)
scripts/ci-local.sh all   # pre-flight: backend + frontend + library pipelines
```

Which script to run when — backend, frontend, library or the mixed release
path — is in [PIPELINES.md](PIPELINES.md).

If GitHub Actions can't start (no token/billing, jobs failing in seconds with
zero steps): don't wait for CI — the local pipeline is the sufficient gate.
See the rule in [PIPELINES.md](PIPELINES.md#se-a-ci-não-consegue-rodar-sem-token-billing-ou-runner).

## Developer scripts

| Script | What it does |
|---|---|
| `mix gate` | the check-only gate: compile warnings, format, credo, tests |
| `scripts/check_assets.sh` | read-only checks on the frontend sources (entrypoints, Tailwind config, debug leftovers) |
| `scripts/ci-local.sh` | runs the same pipelines the CI runs, locally |

## CI

`.github/workflows/ci.yml` has five jobs:

| Job | What it does | Why |
|---|---|---|
| `gates` | `deps.unlock --check-unused`, `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict` | once, not once per partition |
| `backend` | `mix test --partitions 4`, one Postgres per partition | the suite split into four distinct slices |
| `frontend` | `check_assets.sh`, `assets.setup`, `assets.build`, `assets.deploy` in `dev` | the sources are checked and the assets must build with the dev toolchain |
| `library` | `python3 capabilities/tools/validar_biblioteca.py` + its test | the capability library is validated on every change |
| `release` | dev assets → prod compile → `phx.digest` → `mix release` | proves the mixed release path works |

The four backend partitions use `MIX_TEST_PARTITION` and
`mix test --partitions 4`, so each one runs a different slice of the suite
against its own `agent_board_testN` database.

## When something is wrong

| Symptom | Cause | Fix |
|---|---|---|
| `no sync yet` in the header | the last sync threw; see the activity column | the red line names the error (`sync_error`, `issues_unavailable`) |
| a repo with Issues disabled | GitHub answers 404 | handled: issues are optional, pulls still sync |
| `No task is running.` | the runner has no active ticket | not an error; it is the empty state |
| every card says `no review` / `no ci` | the repo has no reviews or CI | accurate, not a bug |
| CI red on every PR | GitHub Billing: payments failed / spending limit | fix Billing & plans; no code change turns it green |
| `sync_error` with 401/403 | `GITHUB_TOKEN` missing, expired, or rate limited | export a fresh token (`gh auth token`) |

## The tests

`mix test` covers each layer: the state mapping (the ticket overlay, the review
and check rollups), the voice summary, the sync against a fake GitHub (no
network), the JSON API controllers, the LiveView (the columns, the empty
state, the voice events, the PubSub broadcast) and the pipeline contract.

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
