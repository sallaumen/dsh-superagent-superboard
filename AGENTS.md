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
| `AgentBoard.AI` | the door to a model: registered calls only, every one a row |
| `AgentBoard.Intake` | a free-text request -> refined spec -> tasks |
| `AgentBoard.Voice` | the spoken summary |
| `AgentBoardWeb.BoardLive` | the real-time UI |
| `AgentBoardWeb.BoardController` | the JSON API (`/api/...`) |

## Gates (must pass before a PR)

Follow [PIPELINES.md](PIPELINES.md) for the required checks, command effects
and pipeline selection. Its
[CI-unavailable procedure](PIPELINES.md#se-a-ci-não-consegue-rodar-sem-token-billing-ou-runner)
is binding when GitHub Actions cannot run.

## Local secrets

- `.env.local` is read by `config/runtime.exs` before any config; it is
  gitignored and never applied in `:test` (`config_env() != :test`).
- `.env` is the committed list of variables -- the example, no secrets.
- The shell wins: a variable already set to a non-blank value is left alone.
- `AGENT_BOARD_ENV_FILE` points the loader at another file (a worktree).

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

## AI calls

- **A call must exist in `AgentBoard.AI.Registry`.** The prompt comes from
  code; a caller cannot invent one. Adding a call is a PR with a test.
- **Every call is a row** in `ai_calls` -- engine, model, tier, tokens,
  latency, parse state. A paid answer without a row is a bug.
- **No retry.** A retried paid request is a second charge.
- **The fast tier is the default.** `:deep` only when the result itself says
  the fast one was not enough.
- **A failure is a reason**, never a fabricated answer: `:not_configured`,
  `:auth_expired`, `:usage_limit`, `{:http, status}`.
- **`Budget.check/1` runs before the network.** Over the cap answers
  `:budget_exhausted` and records nothing.
- **A task that cannot close on its own is dropped**, not created
  half-written (see `AgentBoard.Intake`).

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
- Library validation commands and tool contracts are in
  [capabilities/tools/README.md](capabilities/tools/README.md).
