# AGENTS.md — agent-board

The board for the agent's work, in Elixir. Read this before changing code.

## The layout

| Module | Role |
|---|---|
| `AgentBoard.Board` | the context: repositories, tasks, comments, events, broadcast |
| `AgentBoard.Sync` | the GitHub sync: issues, pulls, reviews, checks, comments |
| `AgentBoard.Sync.Worker` | the Oban job that runs the sync |
| `AgentBoard.Live` | the 10s poller that reads the runner's tickets |
| `AgentBoard.GitHub` | the HTTP client (`body!/1`, rate limits) |
| `AgentBoard.Voice` | the spoken summary |
| `AgentBoardWeb.BoardLive` | the real-time UI |
| `AgentBoardWeb.BoardController` | the JSON API (`/api/...`) |

## Gates (must pass before a PR)

- `mix format --check-formatted`
- `mix credo --strict` (`.credo.exs`, the Phoenix-generated files excluded)
- `mix test`

| Command | What it runs | Modifies files? |
|---|---|---|
| `mix lint` | format check + credo | no |
| `mix gate` | unused deps + compile warnings + format check + credo + tests | no |
| `mix precommit` | the same five, with format and unused deps fixed in place | yes |

CI and pre-push use `mix gate`; `mix precommit` is the fix-up for developers.
Every PR must pass `mix gate` locally and in CI. Which script to run when —
backend, frontend, library or the mixed release path — is in
[`PIPELINES.md`](PIPELINES.md).

**When GitHub Actions cannot run (no token, billing block, runner never
starts): do not wait for CI.** Once you notice the jobs fail in seconds with
zero steps, or no check appears, stop re-triggering and treat the local
pipeline as the sufficient gate: run `scripts/ci-local.sh all` (or the `make`
target for the affected pipeline), fix failures, and proceed — commit, PR and
merge — when it is green. Note in the PR that CI was unavailable and that the
local run is the evidence. Re-run CI manually (`workflow_dispatch`) only after
the blocker is resolved.

## The data

- **Ecto migrations** own the schema. Never edit a migrated table by hand; add a
  migration.
- The task state is two-layered: the **issue** is the baseline (`open` →
  `queued`, `closed` → `done`) and the **ticket** is the overlay (`running`,
  `ready`, `blocked`) while the issue is open. A stopped or archived task keeps
  its state.
- A review rollup is the strongest review (`changes_requested` beats `approved`);
  a check rollup names the failing check.

## Real-time

- The sync (the Oban `Sync.Worker`, every minute) and every task action call
  `Board.broadcast/1`; the LiveView subscribes with `Board.subscribe/1` and
  reloads on `:board_updated`.
- `AgentBoard.Live` polls the agent's tickets every 10s and broadcasts only
  when their hash changed — the runner state reaches the board without waiting
  for the sync. It is idempotent: the same tickets never broadcast twice
  (`live_test.exs`).
- Never poll the database from the browser; push.

## The voice

- The server builds the summary (`AgentBoard.Voice`) and pushes it with
  `push_event/3`; the browser speaks it. The server never runs a TTS engine.

## Types at the boundary

- **A field that is a string must receive a string.** The checks rollup returned
  a tuple `{state, failed}` and the caller put it straight into the
  `checks_state` string column. Every pull failed the changeset and nothing was
  stored -- for three rounds, because the tests that did not fetch checks never
  saw it.
- When a function returns a composite, **decompose it at the call site** and let
  the changeset be the second opinion. The test that finally caught it fed a
  pull with checks through the whole sync.
- If a fetch can fail independently (reviews, checks), **guard the fetch**, not
  the caller: log a `review_error`/`check_error` and continue with an empty
  list.

## What the header shows

- **live / static**: whether the LiveView is connected (the real-time channel
  works) or serving the static render.
- **synced HH:MM · clean / N errors**: the last `sync` event. `clean` means the
  run completed with `errors == 0`; `N errors` counts `issue_error`,
  `pull_error` and `comment_error` in that run. If there is no `sync` event,
  it says `no sync yet`.

The header is the health line: if it says errors, open the activity panel,
where each failing item is one row.

## Network paths

- Every GitHub call goes through `AgentBoard.GitHub`. A 4xx/5xx is **not** a
  body: `body!/1` raises `GitHub HTTP <status>` (or `GitHub rate limited: retry
  after <n>s` for 403/429), so the caller sees the real cause.
- Every function that touches the network must survive a raise: `Sync.sync_repo`
  logs a `sync_error` event and returns `{:error, exception}` so Oban retries;
  `Board.ask` deletes its optimistic placeholder and returns the error. A raise
  that reaches the caller is a bug — the test suite has a case for each.
- Network failures never erase the board's last good state: the overlay is
  skipped, the previous tasks stay.

## Sync isolation

The sync is isolated **per item**, not per repository:

| Failure | Event | The sync... |
|---|---|---|
| an issue fails validation | `issue_error` | continues |
| a pull's reviews/checks fail | `pull_error` | continues |
| a task's comments fail | `comment_error` | continues |
| the repository itself fails | `sync_error` | returns `{:error, exception}` and Oban retries |

Every branch returns `:ok` or logs; nothing swallows an error silently and
nothing takes the whole sync down for one bad item. Each branch has a test in
`sync_repo_test.exs`.

## Boundaries

- The board **reads** the agent's state (the sqlite); it never writes to it.
- The web layer never talks to GitHub directly: it goes through `AgentBoard.Board`
  and `AgentBoard.GitHub`.

## Capabilities library

- Reusable development workflows (architecture, product, UI/UX, testing, code
  review, integrations, operations) live in
  [`capabilities/`](capabilities/CATALOGO.md). The catalog is the entry point;
  each skill loads only its own instructions plus the common contract.
- The optional project contexts (Colmex, forró, Elixir/Phoenix/Oban) are never
  loaded by default — see `capabilities/contextos/README.md`.
- Validate the library with `python3 capabilities/tools/validar_biblioteca.py`
  (tests: `python3 capabilities/tools/test_validar_biblioteca.py`).
