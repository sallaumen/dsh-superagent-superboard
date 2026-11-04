# AGENTS.md — agent-board

The board for the agent's work, in Elixir. Read this before changing code.

## Gates (must pass before a PR)

- `mix format --check-formatted`
- `mix credo --strict` (`.credo.exs`, the Phoenix-generated files excluded)
- `mix test`

`mix lint` runs the first two; `mix precommit` runs the three.

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

## Boundaries

- The board **reads** the agent's state (the sqlite); it never writes to it.
- The web layer never talks to GitHub directly: it goes through `AgentBoard.Board`
  and `AgentBoard.GitHub`.
