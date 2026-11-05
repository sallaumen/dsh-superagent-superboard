# AGENTS.md — agent-board

The board for the agent's work, in Elixir. Read this before changing code.

## Gates (must pass before a PR)

- `mix format --check-formatted`
- `mix credo --strict` (`.credo.exs`, the Phoenix-generated files excluded)
- `mix test`

`mix lint` runs the first two; `mix precommit` runs the three (formatting in
place) plus compile warnings and the unused-dependency check. `mix gate` runs
the three as checks only — it never modifies files, so CI and local pre-push
use `mix gate` while `mix precommit` stays the fix-up command for developers.
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
