# PIPELINES.md — how and when to use each script

This document answers "which script do I run now?". It defines the repository's pipelines, the contract of each script (when to use it, environment, effects, output), and the separation between backend, frontend, library, and the mixed release path.

## Overview

The complete quality gate runs **locally on the proposed revision**. On the
board, `make -j1 check release` runs the following stages in order and stops
on failure. The hosted workflow is a quick second opinion, not the gate.

| Local stage | Evidence |
|---|---|
| Backend | Dependencies and advisories, kit references, compilation, format, Credo, Dialyzer, tests with Postgres (including the secret scan), and Sobelow |
| Frontend | npm audit, source and JS checks, development and production asset builds |
| Library | Installed kit references |
| UI, when selected | A headless WebKit review, with its reason and result on the task |
| Release | Production compilation, digested assets and release packaging |

Every PR gets one [quick GitHub check](.github/workflows/ci.yml): Bash syntax
for the preflight and the Python merge-guard tests on Linux. It needs no
database, dependency installation or paid third-party service. It can also be
run manually. Passing it alone never satisfies the board’s delivery policy.

## Script matrix

| Script | When to use it | Environment | Effects | Expected output |
|---|---|---|---|---|
| `mix setup` | Prepare a development checkout | `MIX_ENV=dev` | installs dependencies, creates and migrates the database, and compiles assets | app ready to start; no projects added |
| `mix ecto.setup` | Create and migrate the development database | `MIX_ENV=dev` | writes the schema; keeps existing projects | empty project list on a fresh database; not a gate |
| `mix ecto.reset` | Deliberately recreate the disposable local database | `MIX_ENV=dev` | **deletes the database** and runs `ecto.setup` | database recreated; outside CI and the pre-flight |
| `mix test` | Test behaviors; accepts a file and filters | `:test` automatically | creates/migrates the test database before the suite | tests green |
| `mix test test/secret_scan_test.exs` | Before committing anything that touched configuration, fixtures or docs with examples; it also runs inside every `mix test`, so `mix precommit`, `mix gate` all carry it | `:test` automatically | read-only over the files git tracks or would add (ignored files such as `.env.local` are left alone) | no finding; a finding names file, line and kind of key, never the value |
| `mix lint` | Fast iteration, no database | any | none (read-only) | format and credo green |
| `mix precommit` | Before committing; applies fixes | `:test` automatically | removes orphan dependencies from the lockfile, formats, type-checks, and runs tests | formatting applied + gates green |
| `mix gate` | Full local backend checks | run with `MIX_ENV=test` | compiles and creates/migrates the test database; does not change sources | dependencies, agent references, warnings, format, credo, Dialyzer, and tests green |
| `mix dialyzer` | Type check; part of `mix gate` and `mix precommit` | `MIX_ENV=test` | builds the PLT in `_build/plts` the first time (minutes), then checks in seconds; does not change sources | `Total errors: 0`; a schema referenced as `t()` defines `@type t` |
| `mix sobelow --exit` | Security scan; part of `make backend` and the pre-flight | `MIX_ENV=test` | static analysis, without fixing sources | scan completes with no findings that fail the command |
| `mix agent_kit.check` | Checks the versioned installation of the agent practices (part of `mix gate`) | dev or test | read-only; does not start the application or call models | index and entry points consistent with the dependency and configuration |
| `mix deps.unlock --check-unused` | Review the lockfile (part of `mix gate`) | `:test` | none | no orphan dependencies |
| `mix assets.setup` | First frontend run | `MIX_ENV=dev` | downloads the tailwind/esbuild binaries | tools installed |
| `mix assets.build` | When changing CSS/JS | `MIX_ENV=dev` | writes `priv/static/assets/` | bundle built without error |
| `mix assets.deploy` | Validate the production asset path | `MIX_ENV=dev` | minifies + `phx.digest` | digest manifest generated |
| [scripts/check_assets.sh](scripts/check_assets.sh) | When changing CSS/JS (first step of the frontend pipeline) | local machine with `node` on the PATH | none (read-only) | entries present, tailwind pipeline configured, authored JS without debug, JS tests and Harness worker-title contract tests (Node 22.19+ or 24+ with `node:sqlite`) green |
| `make help` | Discover the available targets | `make` | none | target names and a reference to this matrix |
| `make backend` | Full backend checks, including Sobelow | pins `MIX_ENV=test` | those of `mix gate` (Dialyzer included) and Sobelow | backend checks pass |
| `make frontend` | Validate sources and production assets | pins `MIX_ENV=dev` | asset checks, setup, build, and deploy | assets built |
| `make library` | Validate references to the pinned dependency | dev | read-only | references valid |
| `make release` | Exercise production packaging | assets in dev; application in prod | builds the release and overwrites the previous artifact | release artifact built |
| `make check` | Run backend, frontend, and library | environments defined by each target | those of the three pipelines | PR checks green; does not include release |
| `make coverage` | Audit test gaps | local machine | generates `cover/` (HTML) | report generated; exit != 0 if total coverage falls below 90% (Elixir's default threshold) |
| [scripts/ci-local.sh](scripts/ci-local.sh) `[pipeline]` | Full pre-flight before opening a PR | local machine | those of the scripts above (release is opt-in) | all pipelines green |
| [scripts/service.sh](scripts/service.sh) | Start the server via launchd, or for manual diagnosis | `mix` on the PATH; `MIX_ENV=dev` and `PORT=4099` by default; waits for Postgres at `AGENT_BOARD_DB_HOST`:`AGENT_BOARD_DB_PORT` (`127.0.0.1:5434`) for up to `AGENT_BOARD_DB_WAIT` seconds (300); with `AGENT_BOARD_LOG` set (the plist sets it), rotates the log above `AGENT_BOARD_LOG_MAX_BYTES` (50 MB); all overridable from the environment | with `AGENT_BOARD_LOG`, moves the log to `<log>.1` if it passed the limit (one old copy) and starts writing to it; waits for the database (`pg_isready`, or `nc` without it) and exits with 75 if it does not respond, so launchd tries again; then `deps.get`, `ecto.migrate`, and starts a persistent process with `PHX_SERVER=true`; accesses configured services | server active; not a gate and does not run in CI |
| [scripts/agent/keepalive.sh](scripts/agent/keepalive.sh) | Restart the agent orchestrator when it went down without a deliberate `stop`; launchd runs it at login and every 5 min ([ops/com.dsh.superagent.plist](ops/com.dsh.superagent.plist)) | `python3` on the PATH; `DSH_SUPERAGENT_HOME` points to the prototype (default in `scripts/agent/_common.sh`); log in `DSH_SUPERAGENT_KEEPALIVE_LOG` (`~/Library/Logs/dsh-superagent-keepalive.log`) | asks `scripts/dsh-superagent status`; if the agent went down and the `manually-stopped` marker is absent, runs `start --respect-stop`, which opens `dsh` in the `dsh-superagent` tmux session; status 2 or 3 only logs; one log line per action, log moved to `.1` above 1 MB | agent up, or nothing to do; not a gate and does not run in CI |

The backend gate runs `mix hex.audit` on the lockfile; the frontend preflight runs `npm audit --prefix scripts/agent/alpine` on the optional Harness installer. Both query package advisories and must pass. An unavailable registry is not a clean result.

Before delivering any PR, run **`scripts/ci-local.sh all`**. It runs backend,
frontend, and library sequentially, followed by the [conditional UI review](#automatic-local-ui-review). It stops at the first failure. During
the work, use `make` for an isolated pipeline. When the deployment path changes,
also run `scripts/ci-local.sh release`.

Prerequisites: dependencies installed with `mix deps.get`, Elixir/OTP and `mix`
on the PATH, Postgres reachable at `127.0.0.1:5434` with user/password `board`,
`pg_isready` on the PATH for the backend pre-flight. The library uses Mix; its
content and installer tests belong to the kit repository. Usage and exit codes:
an omitted target is equivalent to `all`; success returns 0, an unknown target
returns 2, and a failure of one command stops the execution with a non-zero
status.
Service installation is in [the operations guide](docs/operations.md#run-as-a-service); the
pre-flight does not start or restart the service.

## If CI cannot run (no token, billing, or runner)

Do not repeatedly trigger a workflow that cannot start. Run the commands
named in the project's merge policy on the current head. For the board that
is `make -j1 check release`; record the commit and results in the PR. A
successful local run needs no Actions receipt. An absent workflow is normal.
Missing local tools, a failed test, or a result from another revision is
never a pass.

A failed remote check is not evidence of a billing problem. When GitHub reports
an unstable PR with local-only requirements, the worker only accepts a hosted
failure if GitHub identifies a startup failure or an Actions job with zero
steps and a billing annotation. Unknown failures and actual test failures stop
the merge. Explicitly required hosted checks, reviews, and branch protections
always apply. The GitHub API is still needed to verify and merge the PR.

## Adopting this design in another project

No Actions workflow, Makefile, or kit installation is required in a managed
repository. Configure its existing commands on the board machine using the
[per-project policy](docs/agent/merge-checks.md). A policy already present on
the destination branch takes priority. With neither policy, the worker does
not merge. The commands belong to that project: a Rust or JavaScript ticket
does not need the board's Elixir pipeline.

## History

- Single job (`gates`) replaced by separate pipelines (PR #13); release smoke added (PR #14); `make` as the single entry point per pipeline (PR #15); this matrix created afterwards. Guideline "CI unavailable → local pipeline is the gate" added after the account's billing block. Secret scan added as a test of the suite on 2026-11-12, so that it needs no pipeline of its own; the git history up to that day had no match for its patterns.

## The agent and the AI layer

Two systems run beside the board, and neither is on the board's critical path:

| System | What it does | Documented in |
|---|---|---|
| `dsh-superagent` | watches GitHub for `@sallaumen-agent`, turns the mention into a ticket, runs the executor, opens the PR | [`docs/agent/how-it-works.md`](docs/agent/how-it-works.md) |
| `AgentBoard.AI` | refines a request into a spec, splits it into tasks, answers questions, speaks the board | [`docs/ai-layer.md`](docs/ai-layer.md) |

The board **mirrors** both: the sync reads GitHub, the AI panel reads
`ai_calls`. Stop the board and both keep working.

## Local preflight on the task

Running `scripts/ci-local.sh all` (also the default with no argument) reports
backend, frontend, library and any selected UI review. The Now card shows the current step; the task
inspector lists each outcome and the commit at the start, even before a PR
exists. Single targets and release do not replace this record. A failure still
stops at the first failing command and preserves its exit code.

On a shared host the script writes a small atomic receipt per worktree to
`~/.local/state/superboard/preflight/` (override `SUPERBOARD_PREFLIGHT_DIR`
for both processes). No output, file contents or credentials are included.
Reporting requires Python 3; reporting failures do not fail or skip checks.
The board only reads a receipt for a known task worktree and attempt window.
A newer invocation in the same worktree supersedes the previous one. An
unconfirmed run has no recent heartbeat; it is never reported as passed.
These rows describe the local run only, including uncommitted changes; they
are not GitHub checks or approval to merge a revision.

### Automatic local UI review

After backend, frontend and library pass, `ci-local.sh all` runs a **real
headless WebKit check** if the checkout differs from its merge base with
`origin/main` in a screen, component, route, template, browser interaction,
stylesheet, image/font or interface translation. The comparison includes
committed and uncommitted work, deletions, both sides of renames and nonignored
new files. Fetch the target branch before working. If the base is unavailable
the review runs conservatively. Backend-only changes, focused targets and
release do not acquire this additional stage. The GitHub smoke check does not run this review.

Requires Node, Playwright with its matching WebKit installed locally, the
backend's test database and the frontend's compiled assets. The runner resolves
the project's installed Playwright or the shared pinned local installation;
`SUPERBOARD_PLAYWRIGHT` may point to another installed Playwright package.
No browser is downloaded by a preflight. The app starts on a private loopback
port with disposable fixture rows in a rolled-back test transaction. With these
prerequisites in place the browser step alone is reproducible with
`MIX_ENV=test mix run --no-start scripts/ui-review/run.exs` (use the same
`MIX_TEST_PARTITION` as backend).

The smoke review checks the board, keyboard opening of a task, its inspector,
editing a request without submitting it, and system settings at 1440 and
375 px. It checks a connected LiveView, horizontal overflow and browser errors,
and writes screenshots under ignored `tmp/ui-review/`. This is a common screen
check, not a visual sign-off for every state of a changed feature. The inspector
reports why it ran, which surface failed, or why it was not required. An
unavailable browser or fixture returns 2; a failing surface returns 10–13.
Neither is a pass. A failed required stage still stops before the browser check.
