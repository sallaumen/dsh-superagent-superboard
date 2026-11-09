# Superagents per project: management plan for the board

**Status:** phases 1–5 implemented: registry, status/ticker/panel, actions to
start/stop/pause/resume/scale, real provisioning through the board, removal
with archiving, and boot reconciliation without LaunchAgents per profile. Real
provisioning was exercised with a temporary repository (agent ready, correct
repo/config/workers) and the repo was archived afterwards. The review and the
gates are in the PR history.
**Date:** 2026-11-08.
**Scope:** turn the manual configuration of a `dsh-superagent`
(profile, SQLite database, port, process and keepalive) into a board resource,
with multiple projects and multiple board owners.
**Out of scope for now:** multi-repository support inside a single
superagent, running the superagent as a child process of the board, storing a
GitHub token in the board, exposing the API on the network.

## 1. The real problem

Today DeepSeek is the board's default executor (`Executors.default/0 == "dsh"`),
but **who executes** is an external `dsh-superagent`, one per repository. The
second `o_colmex` instance was created by hand:

- profile `superagent-colmex`, port 3083, state in
  `~/.dsh/state/superagent-colmex`;
- one `LaunchAgent` per profile (`ops/com.dsh.superagent*.plist`);
- repository, CLI, executor, policy and prompt configuration done through the
  DSH panel/API;
- the board discovers the databases by wildcard
  (`~/.dsh/state/superagent*/orchestrator.sqlite`) and the repository list
  through the `dsh_repositories` setting.

This works for two projects of one owner, but it is not an operable product:
there is no provisioning, per-project status, per-project start/stop, worker
scaling, access validation, rollback or isolation between owners.

## 2. Proposed architecture decisions

### 2.1 One board per owner; not a multi-tenant board

"More people using the board in their own homes" should mean **one board
installation per person**, with that person's local Postgres database/state. A
single shared board would require authentication, per-tenant authorization,
secret encryption, per-actor audit and process isolation — a different
product, and the current API writes to localhost without authentication.

**Recommendation:** keep the board single-owner and document the repeatable
installation. Only consider multi-tenant in a future phase, with authentication
and an explicit trust boundary.

### 2.2 One superagent per repository; scale is `maxWorkers`

The `dsh-superagent` is designed for **one repository** per instance. Two
superagents must not run on the same repository: GitHub notifications, the
state lock and the sessions collide.

"Increasing the number of processes" means **increasing
`executor.maxWorkers`** for that superagent (concurrent sessions), not creating
several orchestrators for the same repo. The board must say this on screen:
"1 superagent, N sessões simultâneas" ("1 superagent, N concurrent sessions").

### 2.3 The board is the control plane, not the process parent

The board must not start `dsh` as a direct child. It talks to the DSH's
**official manager** (`scripts/dsh-superagent`) and to the superagent's
**management API**:

- `start|stop|restart|status` per profile/port;
- `PUT settings/executor` for `maxWorkers`, directory and prepare;
- `GET state` for health, repository, load and setup.

The process stays in tmux, outside the board. If the board restarts, the
superagent keeps running; when the board comes back, it reconciles desired
state with observed state. After a reboot, the board's **only** `LaunchAgent`
starts the board, which starts the desired superagents. This replaces N plists
per project.

### 2.4 A single, testable adapter

`AgentBoard.Superagents.Manager` is a behaviour with two implementations:

- `AgentBoard.Superagents.DshManager` — real commands and HTTP API;
- `AgentBoard.Superagents.FakeManager` — tests; creates temporary
  profiles/ports/states and simulates start/stop/scale.

No LiveView or worker calls `System.cmd/3` directly. The manager is injected by
configuration, like the runners' `runner_launcher`.

## 3. Responsibility map

| Concept / table | Owner | Readers | Writers |
|---|---|---|---|
| `repositories` | `Board` | `BoardLive`, `Routing`, `Superagents` | `Board` (action `add_repository`) |
| `tasks` | `Board` | board, routers, reports | `Board`/`Actions` and sync overlays |
| `superagents` | `Superagents` | board, `Routing`, `AgentState`, `Actions` | `Superagents` (via actions) |
| `superagent_events` | `Superagents` | audit UI | `Superagents` |
| `runner_executions` | `Runners` | inspector, Hoje (Today) | `Runners` (action `dispatch_task`) |
| DSH ticket SQLite | DSH process (external) | `AgentState` (read-only) | DSH |
| usage/costs | `Usage` | panels, router, summary | ledger readers |
| GitHub (issues/PRs) | `Sync` | board | `Sync`/`Actions` |

Dependency direction:

```
web (LiveView) → Superagents → Manager (behaviour) → DSH manager/API
web → Board → Repo
Routing → Superagents (observed state) + Usage
AgentState → Superagents (list of explicit state dirs)
```

`Superagents` is the only owner of the `superagents` table and of the lifecycle.
The board does not import `dsh` details; the adapter is the boundary.

## 4. Data model

### 4.1 `superagents`

One row per project/repository.

| Field | Type | Rule |
|---|---|---|
| `id` | bigint | PK |
| `repository_id` | FK repositories | **unique**, one agent per repo |
| `profile` | string | unique; `superagent-<slug>` validated |
| `port` | integer | unique; configurable range, 127.0.0.1 |
| `state_dir` | string | allowed root; 0700 permission |
| `desired_state` | enum | `running`, `paused`, `stopped` |
| `observed_state` | enum | `unknown`, `starting`, `ready`, `paused`, `error`, `stopped` |
| `observed_at` | utc_datetime | last read |
| `last_error` | text | readable reason, no secret |
| `max_workers` | integer | 1..N; default 3 |
| `poll_seconds` | integer | 60..3600 |
| `setup_version` | integer | version of the applied template |
| `created_by` | string | local actor (owner) |
| timestamps | | |

Indexes: `repository_id` unique, `profile` unique, `port` unique,
`(desired_state, observed_state)`.

### 4.2 `superagent_events`

Append-only audit: `superagent_id`, `action` (`provision`, `start`,
`stop`, `pause`, `resume`, `scale`, `delete`, `reconcile`, `error`), `from`,
`to`, `actor`, `detail`, `inserted_at`. The UI shows the latest events; the
board's action log remains the record of decisions.

### 4.3 Explicit `AgentState`

Remove the wildcard as the source of truth. `AgentState.snapshot/0` now
receives/reads the `state_dir`s from `Superagents`:

```elixir
AgentState.read_normalized(Superagents.state_paths())
```

The current wildcard is useful as a migration, but it does not serve a board
with multiple owners: it scans the home directory and can read another product's
database.

### 4.4 Migrating the two current agents

A data migration creates the two rows (`superagent` → arena, port 3082;
`superagent-colmex` → o_colmex, port 3083), with the current state dirs. The
second profile's `LaunchAgent` can be removed after the board successfully
reconciles both; until then, both paths coexist.

## 5. Lifecycle and reconciliation

### 5.1 States

Desired: `running`, `paused`, `stopped`.

Observed: `unknown`, `starting`, `ready`, `paused`, `error`, `stopped`.

Rules:

- `desired=stopped` → manager stop; observed `stopped`.
- `desired=paused` → `POST executor/pause {paused:true}`; observed `paused`
  (the process stays alive, without taking new work).
- `desired=running` → start if needed; remove pause; observed `ready`
  when `/state.health` and setup are ok.
- `setup.problem != nil` → observed `error`; the UI shows the problem and the
  required command/action; it does not restart in a loop.
- `unreachable` > 3 reads → `error` with "não respondeu" ("did not respond");
  the reconciler tries `restart` with backoff (max. 3) and then stops.
- `starting` for more than X seconds → timeout `error`, never an optimistic
  "ready".

### 5.2 Reconciler

A `SuperagentReconciler` (GenServer or Oban cron every 30–60 s):

1. reads rows with `desired_state != observed_state` or stale health;
2. runs **one** transition per row, with a logical lock (`updated_at`/Oban
   unique);
3. writes the event and the observed state;
4. never blocks a LiveView; the command goes to a Task/Oban with a timeout;
5. on board startup, reads all `desired=running` rows and starts the ones that
   are `stopped/unreachable`, with jitter.

The manager is already idempotent (`start` finds an existing process). The
board also uses a unique per profile/port and a `GenServer`/Oban unique to avoid
two simultaneous actions.

### 5.3 Start/stop/pause/scale

Registry actions (see §7):

- `provision_superagent` — creates profile/state/port, validates access, starts,
  configures via API and writes the row; rollback on failure.
- `start_superagent` — desired running; manager start; waits for `/state`.
- `stop_superagent` — desired stopped; manager stop; preserves state.
- `pause_superagent` / `resume_superagent` — logical pause in the DSH.
- `scale_superagent` — `maxWorkers` via `PUT settings/executor`; validates the
  range.
- `remove_superagent` — stop; archives the state dir; does not delete data by
  default.

## 6. Provisioning a new project

Flow in one confirmed red action, executed outside the LiveView:

1. **Validate** `owner/name`; is the repo on the board? No? offer
   `add_repository` first.
2. **Validate the bot**: `gh-agent api repos/:owner/:name` and `permission=write`;
   with no secret in the board, the bot's CLI stays in the DSH environment.
3. **Allocate** profile (`superagent-<slug>`), a free port in the range
   (`dispatch_superagent_port_start` etc.), a state dir under an allowed root.
4. **Create the profile** from a versioned template (do not copy
   `~/.dsh/profiles/superagent` blindly): port, stateDir, model provider.
5. **Start** via the manager and wait for `GET /state`; timeout with rollback.
6. **Configure** GitHub source (repo, CLI), executor (directory, prepare,
   `maxWorkers`), policy (allowed list) and prompts (template + version).
7. **Check** `setup.problem == nil`, health ready, and that the repo is the
   expected one.
8. **Write** `superagents`, event `provision`; return the panel/port and the
   link to the project.

The project's clone/prepare needs an existing, clean directory. The board must
not clone personal repositories without an explicit choice; the form asks for
the local path or offers "use `~/src/<name>`" with confirmation.

### 6.1 Port allocation

One range per board (`3082..3182`, configurable), `lsof`/bind check and a
database unique constraint. The new profile never reuses a port from a `running`
row; a `stopped` row may reuse one after confirmation.

### 6.2 Rollback

Failure in any step after profile/state:

- best-effort `stop`;
- keeps the state dir/logs for diagnosis;
- writes `observed=error`, `last_error` and an event;
- does not delete the repo/tasks;
- allows an idempotent `retry` of the action.

## 7. Actions and confirmation contract

Every new action goes into `AgentBoard.Actions`, with risk, a sentence with real
values, audit and a test in `actions_test.exs`.

| Action | Risk | Effect | Confirmation |
|---|---|---|---|
| `provision_superagent` | red | creates profile/process/port/state and configures the DSH | sentence with repo, profile, port, path |
| `start_superagent` | red | starts a process that may spend DeepSeek | sentence with repo/profile |
| `stop_superagent` | red | interrupts work in progress | sentence with repo and active tickets |
| `pause_superagent` | yellow | stops taking new work, process alive | click; undo with resume |
| `scale_superagent` | yellow | changes `maxWorkers` | click; −/+ undoes |
| `remove_superagent` | red | stops and archives the profile/state | sentence; does not delete by default |

The project UI must use `AgentAction` (two steps) for the red ones, like local
dispatch; nothing starts on the first click.

## 8. Board UI

New **Projetos / Superagents** (Projects / Superagents) section (or a tab in
**Executores** — Executors):

- list per repository: avatar/slug, observed status (dot +
  "ligado/desligado/pausado/erro" — on/off/paused/error), port, workers, last
  poll, open tickets, last error message;
- buttons: **Ligar** (start), **Parar** (stop), **Pausar** (pause),
  **Retomar** (resume), **Workers −/+**, **Remover** (remove, with
  confirmation);
- **Adicionar projeto** (add project): repository (select of the ones the bot
  accesses), local path, initial workers, automatic port; a preview of what will
  be created;
- **DeepSeek** in the task: if the repository has a `ready` superagent, the
  composer suggests DeepSeek and explains "1 agente, N sessões" ("1 agent,
  N sessions"); if it is `stopped/error`, it shows the reason and the start
  button;
- **Custo/uso** (cost/usage): DeepSeek in estimated US$ (or "desconhecido" —
  unknown), without adding it to Claude/Codex; Codex quota separate;
- mobile: stacked cards, 44 px controls, no overflow.

## 9. Multi-owner and security

- **Recommended:** one installation per person, under their user, with their own
  `~/.dsh`, `~/.agent_board`, Postgres and GitHub bot. The local board still has
  no network authentication, but listens only on `127.0.0.1`.
- **If a board is shared:** before any other person's project, add
  authentication, roles (owner/viewer/operator), isolation per owner/repo, actor
  audit and segregation of state dirs/ports. The `superagents` model gains
  `owner_id`; `repositories` gains a tenant. That is a separate product, not a
  flag.
- **Secrets:** the board never stores a GitHub token. The agent CLI
  (`gh-agent`) and the DSH login stay in the owner's environment; the board only
  checks `api user`/permission and records the public login.
- **File/process boundary:** profile/state/port come from an allowlist and
  validation; no `System.cmd` with an interpolated input string; arguments as
  lists; state dirs 0700; root under the user's home.
- **Network:** superagent and board on `127.0.0.1`; no public tunnel.

## 10. Validation and tests

### 10.1 Unit/context tests (no real DSH)

- `SuperagentsTest`: unique repo/profile/port; desired/observed transitions;
  rollback; delete preserves state.
- `FakeManagerTest`: provision creates temporary profile/port/state; idempotent
  start; stop; scale; manager down; timeout.
- `ActionsTest`: each new action, risk, sentence, refusal without confirmation,
  audit; no LiveView calls the manager.
- `AgentStateTest`: reads only the state dirs from the database; does not scan
  the home directory; two repos, separate tickets; missing database.
- `RoutingTest`: DeepSeek only for repos with a `ready` agent; paused/error/off
  appears with a reason; the composer chooses dsh when ready.
- `BoardLiveTest`: card per project, start/stop/pause/scale, confirmation;
  mobile 390 px.

### 10.2 Integration test with a fake manager

Create board → add repo → provision → list status → pause → resume → scale
workers → stop → restart the board (new process) → reconcile without
duplicating → remove. All with temporary state dirs.

### 10.3 Real E2E (once, per machine)

- Add a test project whose bot has access.
- Provision through the board; check `GET /state`, health, repo, port.
- Create a smoke task; see the ticket in the DSH and on the board.
- Stop through the board; check that the process stopped and that a new start
  does not duplicate it.
- Restart the board; check reconnection and status.
- Measure provisioning time and failures.

### 10.4 Acceptance criteria

1. An owner adds a repository and provisions DeepSeek **without editing files
   by hand**.
2. The board shows on/off/paused/error per project, with a reason.
3. Start/stop/pause/resume and workers work and are audited.
4. A second project on the same board does not interfere with the first (port,
   state, tickets, GitHub tickets).
5. Restarting the board does not kill superagents and does not create
   duplicates.
6. A provisioning failure leaves no orphan process and no "ready" row.
7. Another person installs the board in their own home and repeats the flow with
   their own bot, without changing code.
8. No token in the database/log; nothing listens outside localhost.

## 11. Phases and PRs

| Phase | Deliverable | Proof |
|---|---|---|
| 0 | This document + ADR 0005 + owner decisions | review accepted |
| 1 | `superagents`/`superagent_events` migration; context; seed of the two current ones; `AgentState` reads state dirs from the database | tests; board comes up with both |
| 2 | Manager behaviour + DshManager/Fake; status poller; read-only cards; status reconciliation | tests + screen |
| 3 | start/stop/pause/resume/scale actions; confirmations; UI | tests + E2E |
| 4 | Provisioning (profile/port/state/setup) + rollback + "Adicionar projeto" | fake + real |
| 5 | Removal/archiving; boot reconciliation; remove per-profile plists; installation docs | reboot E2E |
| 6 | Multi-owner: only if the owner chooses a shared board; auth/tenant/security | threat model + tests |

Each phase is a squash PR, green gate, service updated. Phase 1 does not change
the UI; phase 4 is the only one that creates external processes.

## 12. Risks and mitigation

| Risk | Mitigation |
|---|---|
| Duplicate superagent on the same repo | database unique + idempotent manager + lock |
| Port taken | allocator + bind + clear error + retry |
| Orphan profile/state | rollback stops and archives; never deletes without confirmation |
| Board restart kills the process | process in tmux, external manager, reconciliation |
| Agent without repo access | `gh-agent` validation before creating; UI explains |
| Infinite pending setup | timeout, `observed=error`, panel link |
| Token leak | no token in the board; CLI in the owner's home |
| Shared board without auth | forbidden until phase 6; one instance per person |
| DeepSeek cost/consumption | estimated usage in the ledger; no summing currencies; per-project ceiling in the DSH |

## 13. Questions that need your decision

1. **One installation per person** (recommended) or a shared multi-owner board?
   If shared, phase 6 becomes a prerequisite, not optional.
2. **One bot per person** (recommended) or a shared bot? The bot is who receives
   the notifications; sharing mixes permissions.
3. **Auto-start on boot**: should the board start every `desired=running`
   project? Recommended yes; the only LaunchAgent is the board's.
4. **State dir root**: `~/.dsh/state/superagent-<slug>` (current) or
   `~/.agent_board/superagents/<slug>`? The second decouples from the DSH, but
   requires configuring the profile.
5. **Removal**: archive the state (recommended) or delete it? The default does
   not delete.
6. **Port range** and maximum workers per project.
7. **Plan approval**: can I start with phase 1 (data + explicit reads), without
   touching the UI or creating processes?

## 14. What I would not do

- Run `dsh` as a child of the board (`Port`/`System.cmd` that dies on restart).
- Create N `LaunchAgents` per project; one board, one reconciler.
- Scan `~/.dsh` in production; explicit state dirs.
- Store a GitHub token in Postgres.
- Pretend that "more processes" = more superagents on the same repo; it is
  `maxWorkers`.
- Open the API to the network before authentication.
- Delete state/worktrees automatically on removal.

## 15. Evidence of the current state (baseline)

- `mix xref graph --format cycles --label compile-connected` → **No cycles found**.
- Second profile in `~/.dsh/profiles/superagent-colmex`, port 3083,
  `repository sallaumen/o_colmex`, health ready, `problem none`.
- `AgentState.paths/0` today reads
  `~/.dsh/state/superagent*/orchestrator.sqlite` (wildcard) — **temporary**;
  phase 1 replaces it with explicit rows.
- `dsh_repositories` in Configurações → Despacho local (Settings → Local
  dispatch); the `o_colmex` composer already suggests DeepSeek.
- `ops/com.dsh.superagent.colmex.plist` exists as proof; phase 5 removes
  per-profile plists in favor of the board reconciler.
