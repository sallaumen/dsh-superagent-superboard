# PIPELINES.md — how and when to use each script

This document answers "which script do I run now?". It defines the repository's pipelines, the contract of each script (when to use it, environment, effects, output), and the separation between backend, frontend, library, and the mixed release path.

## Overview

| Pipeline | What it validates | Canonical script | `make` target | CI job |
|---|---|---|---|---|
| Backend | Orphan dependencies, agent practices, warnings, formatting, credo, Dialyzer, tests, and Sobelow | `mix gate` + `mix sobelow --exit` | `make backend` | `gates` + `backend` (Dialyzer local only for now) |
| Frontend | Asset sources, setup, build, and deploy | `scripts/check_assets.sh` + asset tasks | `make frontend` | `frontend · assets` |
| Library | References to the versioned kit | `mix agent_kit.check` | `make library` | `biblioteca de capacidades` (capability library) |
| Mixed (release) | The combined path of a deploy | release sequence (below) | `make release` | `release · caminho misto` (mixed path) |
| All | Backend, frontend, and library, before delivering | `scripts/ci-local.sh all` | `make check` | `gates`, `backend`, `frontend`, `library` |

The executable commands live in [Makefile](Makefile),
[scripts/ci-local.sh](scripts/ci-local.sh), and the
[workflow](.github/workflows/ci.yml). CI splits the backend checks between
`gates` (dependencies, compilation, format, credo, and Sobelow) and `backend`
(tests in partitions with `MIX_TEST_PARTITION`, each with its own database).
Locally, `make backend` and the pre-flight run the whole suite and Sobelow.
The frontend uses `MIX_ENV=dev`; `release` is a separate job in CI and opt-in in the pre-flight.

The tests in `test/pipeline_contract_test.exs` verify the expected aliases and
commands in the workflow. They do not compare this documentation or every script
body: changes to those contracts require checking the consumers.

## Script matrix

| Script | When to use it | Environment | Effects | Expected output |
|---|---|---|---|---|
| `mix setup` | Prepare a development checkout | `MIX_ENV=dev` | installs dependencies, prepares the database with seeds, and compiles assets | app ready to start; outside CI because it applies seeds |
| `mix ecto.setup` | Create/migrate and seed the development database | `MIX_ENV=dev` | writes to the database; runs `priv/repo/seeds.exs` | database and seeds ready; not a gate |
| `mix ecto.reset` | Deliberately recreate the disposable local database | `MIX_ENV=dev` | **deletes the database** and runs `ecto.setup` | database recreated; outside CI and the pre-flight |
| `mix test` | Test behaviors; accepts a file and filters | `:test` automatically | creates/migrates the test database before the suite | tests green; CI uses partitions |
| `mix lint` | Fast iteration, no database | any | none (read-only) | format and credo green |
| `mix precommit` | Before committing; applies fixes | `:test` automatically | removes orphan dependencies from the lockfile, formats, type-checks, and runs tests | formatting applied + gates green |
| `mix gate` | Backend checks; CI splits its steps across jobs | run with `MIX_ENV=test` | compiles and creates/migrates the test database; does not change sources | dependencies, agent references, warnings, format, credo, Dialyzer, and tests green |
| `mix dialyzer` | Type check; part of `mix gate` and `mix precommit` (the `gates` job runs it once the workflow change lands: it needs a token with the `workflow` scope) | `MIX_ENV=test` | builds the PLT in `_build/plts` the first time (minutes), then checks in seconds; does not change sources | `Total errors: 0`; a schema referenced as `t()` defines `@type t` |
| `mix sobelow --exit` | Security scan; part of `make backend` and the pre-flight | `MIX_ENV=test` | static analysis, without fixing sources | scan completes with no findings that fail the command |
| `mix agent_kit.check` | Checks the versioned installation of the agent practices (part of `mix gate` and the gates job) | dev or test | read-only; does not start the application or call models | index and entry points consistent with the dependency and configuration |
| `mix deps.unlock --check-unused` | Review the lockfile (part of `mix gate` and the CI gates job) | `:test` | none | no orphan dependencies |
| `mix assets.setup` | First run / frontend CI | `MIX_ENV=dev` | downloads the tailwind/esbuild binaries | tools installed |
| `mix assets.build` | When changing CSS/JS | `MIX_ENV=dev` | writes `priv/static/assets/` | bundle built without error |
| `mix assets.deploy` | Validate the production asset path | `MIX_ENV=dev` | minifies + `phx.digest` | digest manifest generated |
| [scripts/check_assets.sh](scripts/check_assets.sh) | When changing CSS/JS (first step of the frontend pipeline) | local machine with `node` on the PATH | none (read-only) | entries present, tailwind pipeline configured, authored JS without debug, JS tests (`node --test test/assets/*.mjs`) green |
| `make help` | Discover the available targets | `make` | none | target names and a reference to this matrix |
| `make backend` | Full backend checks, including Sobelow | pins `MIX_ENV=test` | those of `mix gate` (Dialyzer included) and Sobelow | equivalent to the checks of the `gates` + `backend` jobs |
| `make frontend` | Validate sources and production assets | pins `MIX_ENV=dev` | asset checks, setup, build, and deploy | equivalent to the `frontend` job |
| `make library` | Validate references to the pinned dependency | dev | read-only | equivalent to the `library` job |
| `make release` | Exercise production packaging | assets in dev; application in prod | builds the release and overwrites the previous artifact | equivalent to the `release` job; local opt-in |
| `make check` | Run backend, frontend, and library | environments defined by each target | those of the three pipelines | PR checks green; does not include release |
| `make coverage` | Audit test gaps | local machine | generates `cover/` (HTML) | report generated; exit != 0 if total coverage falls below 90% (Elixir's default threshold) |
| [scripts/ci-local.sh](scripts/ci-local.sh) `[pipeline]` | Full pre-flight before opening a PR | local machine | those of the scripts above (release is opt-in) | all pipelines green |
| [scripts/service.sh](scripts/service.sh) | Start the server via launchd, or for manual diagnosis | `mix` on the PATH; `MIX_ENV=dev` and `PORT=4099` by default; waits for Postgres at `AGENT_BOARD_DB_HOST`:`AGENT_BOARD_DB_PORT` (`127.0.0.1:5434`) for up to `AGENT_BOARD_DB_WAIT` seconds (300); with `AGENT_BOARD_LOG` set (the plist sets it), rotates the log above `AGENT_BOARD_LOG_MAX_BYTES` (50 MB); all overridable from the environment | with `AGENT_BOARD_LOG`, moves the log to `<log>.1` if it passed the limit (one old copy) and starts writing to it; waits for the database (`pg_isready`, or `nc` without it) and exits with 75 if it does not respond, so launchd tries again; then `deps.get`, `ecto.migrate`, and starts a persistent process with `PHX_SERVER=true`; accesses configured services | server active; not a gate and does not run in CI |
| [scripts/agent/keepalive.sh](scripts/agent/keepalive.sh) | Restart the agent orchestrator when it went down without a deliberate `stop`; launchd runs it at login and every 5 min ([ops/com.dsh.superagent.plist](ops/com.dsh.superagent.plist)) | `python3` on the PATH; `DSH_SUPERAGENT_HOME` points to the prototype (default in `scripts/agent/_common.sh`); log in `DSH_SUPERAGENT_KEEPALIVE_LOG` (`~/Library/Logs/dsh-superagent-keepalive.log`) | asks `scripts/dsh-superagent status`; if the agent went down and the `manually-stopped` marker is absent, runs `start --respect-stop`, which opens `dsh` in the `dsh-superagent` tmux session; status 2 or 3 only logs; one log line per action, log moved to `.1` above 1 MB | agent up, or nothing to do; not a gate and does not run in CI |

Before delivering any PR, run **`scripts/ci-local.sh all`**. It runs backend,
frontend, and library sequentially and fails at the first red pipeline. During
the work, use `make` for an isolated pipeline. When the deployment path changes,
also run `scripts/ci-local.sh release`.

Prerequisites: dependencies installed with `mix deps.get`, Elixir/OTP and `mix`
on the PATH, Postgres reachable at `127.0.0.1:5434` with user/password `board`,
`pg_isready` on the PATH for the backend pre-flight. The library uses Mix; its
content and installer tests belong to the kit repository. Usage and exit codes:
an omitted target is equivalent to `all`; success returns 0, an unknown target
returns 2, and a failure of one command stops the execution with a non-zero
status.
Service installation is in [README.md](README.md#run-as-a-service); the
pre-flight does not start or restart the service.

## Why separate backend and frontend

- **Different toolchains**: backend validates with `mix` (compilation + credo + tests with Postgres); frontend validates with `mix`'s own asset tasks (esbuild/tailwind are `runtime: :dev` dependencies). Mixing the two in one job hid which side broke.
- **Attributable failure**: the job name (`backend · partição 2` — the test partition, `frontend · assets`, `biblioteca de capacidades` — the capability library) says what broke without opening logs.
- **Independent cycles**: changing CSS does not need to reprocess the backend, and vice versa.

## When to use the mixed pipeline

The `release` job exists for the path that **needs** both sides together: the deploy. It builds the assets in the dev environment (where esbuild/tailwind exist), compiles production with warnings as errors, digests the assets, and assembles the release (`mix release`). Use it as a smoke test before a deploy and whenever the backend×frontend integration is the risk of the change — not as a gate for every PR (for that, the separate pipelines are faster and more specific).

## If CI cannot run (no token, billing, or runner)

Binding rule, referenced by AGENTS.md: **when you notice that GitHub Actions is not starting, do not wait for it and do not keep re-triggering it.** The local pipeline becomes the official and **sufficient** gate.

How to notice:

- Jobs that fail within seconds with **zero steps** and an account annotation ("payments have failed / spending limit") = billing/token block, not a code defect.
- No check appears on the PR = the runner was never assigned.

What to do:

1. Stop waiting and stop re-triggering runs (it does not help without resolving the block).
2. Run `scripts/ci-local.sh all` and fix until green; include `scripts/ci-local.sh release` when the deployment path changes.
3. Proceed with the delivery authorized in the session using the local run as evidence; record in the PR that CI was unavailable and which local command was run.
4. When the account block is resolved, run CI manually (`workflow_dispatch`) on the latest `main` to restore the external verification.

CI's goal is still to verify in a clean environment; the rule only avoids blocking deliveries because of an account block that is outside the repository.

## Adopting this design in another project

1. Copy the `Makefile` structure: one target per pipeline, keeping the local checks equivalent to the corresponding CI jobs.
2. For the library, follow the [kit installation prompt](https://github.com/sallaumen/elixir-agent-kit/blob/v0.8.0/docs/INSTALL_WITH_AI.md) and run `mix agent_kit.check` after downloading the dependencies.
3. Adapt the release job to your stack: build assets in the environment where the frontend tools exist and assemble the artifact in the production environment.
4. Keep this matrix up to date when a new script appears — a script without a row here has no defined "when to use".

## History

- Single job (`gates`) replaced by separate pipelines (PR #13); release smoke added (PR #14); `make` as the single entry point per pipeline (PR #15); this matrix created afterwards. Guideline "CI unavailable → local pipeline is the gate" added after the account's billing block.

## The agent and the AI layer

Two systems run beside the board, and neither is on the board's critical path:

| System | What it does | Documented in |
|---|---|---|
| `dsh-superagent` | watches GitHub for `@sallaumen-agent`, turns the mention into a ticket, runs the executor, opens the PR | [`docs/agent/how-it-works.md`](docs/agent/how-it-works.md) |
| `AgentBoard.AI` | refines a request into a spec, splits it into tasks, answers questions, speaks the board | [`docs/ai-layer.md`](docs/ai-layer.md) |

The board **mirrors** both: the sync reads GitHub, the AI panel reads
`ai_calls`. Stop the board and both keep working.
