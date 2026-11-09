# Symphony (openai/symphony) × our agent platform

- **Analysis date:** 2026-11-06.
- **Subject:** `openai/symphony` at `be10a1b` (2026-09-15, last commit; same as release `v0.0.3` and the `nightly` prerelease).
- **Method:** read-only clone in a dedicated scratchpad directory (untrusted data: no script, `mix` or `make` from the clone was executed); `gh api`, `gh pr list`, `gh run list` and `git log` for the numbers; reading of our two repositories (`dsh-superagent-prototype` and this board). Symphony paths are relative to the clone root; our paths carry the `dsh:` prefix (prototype) or are relative to this repository.
- **Question:** migrate to Symphony, bring pieces over, or stay as we are.
- **Full research notes** (four files, with the command for each number): the session's notes folder, `research_notes/Symphony versus nossa plataforma/`. This document is the distilled version.

## Summary

**Do not migrate. Stay with our platform and bring five ideas from Symphony, starting with the versioned policy file and the structured "workpad".**

Three facts decide it:

1. **Symphony only talks to Codex.** The only agent client is `SymphonyElixir.Codex.AppServer` (JSON-RPC over stdio); there is no provider abstraction and no `model` field in the schema — the model is a flag of Codex itself inside `codex.command` (`elixir/WORKFLOW.md:34`). Migrating means swapping DeepSeek for Codex/OpenAI and rewriting 1,071 lines of protocol for any other agent.
2. **Symphony persists nothing.** All state (running, claimed, blocked, retries, tokens) lives in the memory of the `Orchestrator` GenServer; a restart wipes the retry queue and the blocked map (`elixir/README.md:33-36`, `SPEC.md` §14.3). Our board exists precisely because it reads the agent's SQLite and keeps history in Postgres; over Symphony it would have nothing to mirror beyond a JSON snapshot.
3. **It is a one-person prototype with no support channel.** Self-declared "low-key engineering preview" and "prototype software intended for evaluation only"; 47 commits, 72% by one author; 4 commits in the last 3 months; issues disabled; 51 discussions with zero replies from any OpenAI account; 0 external PRs merged; 52 days without a commit; the report that `v0.0.3` breaks with current Codex (discussion #134, 2026-10-26) is unanswered.

What is worth bringing over is in the design, not the binary: the `WORKFLOW.md` (policy and prompt versioned in the repository, hot-reloaded), the single "workpad" comment per issue, the reconciliation rules (issue closed mid-run → stop; revalidate before dispatching), the cleanup of workspaces and orphan PRs in terminal state, per-run telemetry (tokens, turns, last event, stall) and `SPEC.md` as a conformance checklist for auditing our lifecycle.

## 1. What Symphony is

### 1.1 Positioning

"Symphony turns project work into isolated, autonomous implementation runs, allowing teams to manage work instead of supervising coding agents" (repository description). The README offers two options: **"Option 1. Make your own"**, having your own coding agent implement `SPEC.md`; and **"Option 2. Use our experimental reference implementation"** in Elixir (`README.md:21-28`). The notice at the top says "Symphony is a low-key engineering preview for testing in trusted environments" (`README.md:11`); the Elixir README says "prototype software intended for evaluation only and is presented as-is. We recommend implementing your own hardened version based on `SPEC.md`" (`elixir/README.md:6-8`); and the CLI only starts with the flag `--i-understand-that-this-will-be-running-without-the-usual-guardrails` (`elixir/lib/symphony_elixir/cli.ex:8-9,111-126`).

The main product is **`SPEC.md`** (2,312 lines, "Status: Draft v1 (language-agnostic)", normative with RFC 2119): it defines a "scheduler/runner and tracker reader" whose boundary is explicit — "Ticket writes (state transitions, comments, PR links) are typically performed by the coding agent through provider-native tools ... A successful run can end at a workflow-defined handoff state (for example `Human Review`), not necessarily `Done`" (`SPEC.md:36-44`). Non-goals: "Rich web UI or multi-tenant control plane", "General-purpose workflow engine", "Built-in business logic for how to edit tickets, PRs, or comments" (`SPEC.md:60-69`).

### 1.2 Languages and stack

| Item | Value | Source |
|---|---|---|
| Languages (bytes, GitHub API) | Elixir 914,026; Python 19,585; CSS 8,252; Shell 657; Makefile 650; Dockerfile 600 | `gh api repos/openai/symphony/languages` |
| Python | a single file, `.codex/skills/land/land_watch.py` (async helper that calls `gh`); not a runtime | `find . -name '*.py'` |
| Elixir / OTP | `elixir: "~> 1.19"`; `mise.toml`: `erlang = "28"`, `elixir = "1.19.5-otp-28"` | `elixir/mix.exs:8`, `elixir/mise.toml:1-3` |
| Runtime dependencies | `phoenix ~> 1.8.0` (1.8.4), `phoenix_live_view ~> 1.1.0` (1.1.25), `bandit ~> 1.8` (1.10.3), `req ~> 0.5`, `jason`, `yaml_elixir ~> 2.12`, `solid ~> 1.2` (Liquid templates), `ecto ~> 3.13` (`embedded_schema` only, to validate config; no `ecto_sql`) | `elixir/mix.exs:70-87`, `elixir/mix.lock` (39 packages) |
| Packaging | `burrito ~> 1.5` (`only: :prod`), 4 targets: `macos_arm64`, `macos_x86_64`, `linux_arm64`, `linux_x86_64` | `elixir/mix.exs:106-120` |
| Size | 51 `.ex` (13,070 lines in `elixir/lib`); 31 `.exs` (15,275 lines in `elixir/test`) | `wc -l` |

Without Phoenix, LiveView and Bandit the service would lose only the web dashboard; the core depends on Req, Jason, YamlElixir, Solid and Ecto-schema.

### 1.3 Architecture

An OTP application with a single authority process and N ephemeral tasks:

- `SymphonyElixir.Application` starts, `one_for_one`: `Phoenix.PubSub`, `WorkflowStore`, `AgentRuntimeSupervisor`, `HttpServer`, `StatusDashboard` (`elixir/lib/symphony_elixir.ex:35-51`).
- `AgentRuntimeSupervisor` (`one_for_all`) groups a `Task.Supervisor` and the `Orchestrator` GenServer: if the scheduler crashes, all agents crash with it (`elixir/lib/symphony_elixir/agent_runtime_supervisor.ex:15-33`).
- `Orchestrator` (1,990 lines) is the only state mutator: `running`, `claimed`, `blocked`, `retry_attempts`, `completed`, `codex_totals`, `codex_rate_limits`, all in memory (`elixir/lib/symphony_elixir/orchestrator.ex:29-44`).
- `AgentRunner` runs one item: `Workspace.create_for_issue` → `before_run` hook → Codex session with N turns → `after_run` hook (`elixir/lib/symphony_elixir/agent_runner.ex:22-56`).
- `Tracker` is a **read** behaviour (`fetch_issues_by_states/1`, `fetch_issues_by_ids/1`) with compiled adapters `asana`, `github`, `gitlab`, `jira`, `linear`, `memory`; "The orchestrator only depends on the read callbacks" (`elixir/lib/symphony_elixir/tracker.ex:2-31`).
- `Codex.AppServer` (1,071 lines): minimal client for the `codex app-server` protocol (JSON-RPC 2.0 over stdio).
- `WorkflowStore` re-reads `WORKFLOW.md` every 1 s by `{mtime, size, phash2}`; an invalid reload keeps the last good one; an invalid one at boot prevents startup (`elixir/lib/symphony_elixir/workflow_store.ex:13,66-75,169-180`).
- `PromptBuilder` renders the `WORKFLOW.md` body with Solid (`strict_variables`, `strict_filters`) and the `issue` and `attempt` variables (`elixir/lib/symphony_elixir/prompt_builder.ex:8-25`).

Data flow (text):

```
WORKFLOW.md ─(poll 1s)─▶ WorkflowStore ─▶ Config (typed Ecto schema)
                                              │
Tracker API ◀─ fetch_issues_by_states(active) ┐▼
            ◀─ fetch_issues_by_ids(running) ──┤ Orchestrator (GenServer)
                                              │  tick: reconcile running/blocked
                                              │        → validate → fetch → sort → dispatch
                                              │  :DOWN normal → continuation retry (1 s)
                                              │  :DOWN abnormal/stall → backoff 10 s·2^(n-1) ≤ 5 min
                                              ▼
                                   Task.Supervisor.start_child
                                              ▼
                                   AgentRunner.run(issue, attempt, worker_host)
                                     ├ Workspace.create_for_issue (root/<key>, hook after_create)
                                     ├ hook before_run
                                     ├ AppServer: bash -lc "unset <segredos> && exec codex app-server"
                                     │   initialize → thread/start{approvalPolicy,sandbox,cwd,dynamicTools}
                                     │   turn 1: rendered prompt · turn n: "continuation guidance"
                                     │   item/tool/call → adapter.execute_agent_tool (host-side, with credential)
                                     │   after each turn: refetch the issue; continues only if active and routable
                                     └ hook after_run
```

### 1.4 Execution model

**How it receives work.** Polling only; there is no webhook receiver anywhere (the router exposes only the dashboard and `/api/v1/*`, `elixir/lib/symphony_elixir_web/router.ex:17-41`). Every `polling.interval_ms` (default 30 s; OpenAI uses 5 s) the Orchestrator reconciles active runs, fetches the issues in the `active_states`, sorts by `priority` 1..4, then oldest `created_at`, then `identifier` (`orchestrator.ex:796-814`), revalidates each candidate by id before launching ("Skipping stale dispatch after issue refresh", `orchestrator.ex:907-938`) and dispatches while slots are free: `agent.max_concurrent_agents` (10), a per-state limit (`max_concurrent_agents_by_state`) and a per-SSH-host limit. Eligible = active and non-terminal state, `dispatchable` (defined by the adapter: on GitHub, "not a PR"; on Linear, the assignee matches and no blocker is open), all `required_labels`, not in `running`/`claimed`/`blocked` (`orchestrator.ex:816-868`). `POST /api/v1/refresh` anticipates a cycle.

**How it executes.** Workspace `<workspace.root>/<sanitized key>` per issue, reused across runs; hooks `after_create` (on creation only; failure aborts), `before_run` (failure aborts the attempt), `after_run` and `before_remove` (failures ignored), with `sh -lc`, cwd in the workspace and `hooks.timeout_ms` 60 s (`elixir/lib/symphony_elixir/workspace.ex:15-52,397-418`). Anti-escape validation: canonicalizes paths, rejects a symlink that leaves the root (`workspace.ex:483-510`; `app_server.ex:150-176`). Codex starts as a `Port` with `bash -lc "unset <secret names> && exec <codex.command>"` (`app_server.ex:192-228`); handshake `initialize` → `thread/start` (one thread per run, with `approvalPolicy`, `sandbox`, `cwd`, `dynamicTools`) → `turn/start` per turn (`app_server.ex:275-366`). `turn_timeout_ms` (1 h) is **silence** time and resets on every message; `stall_timeout_ms` (5 min) without an event kills the worker and reschedules it (`orchestrator.ex:581-639`). Approvals are auto-granted **only** with `approval_policy: "never"`; with the default (`reject` map) any approval request, free input or MCP elicitation fails the turn and the issue goes to the in-memory `blocked` map (`app_server.ex:55,565-721,1035-1070`; `orchestrator.ex:659-664,757-779`). Up to `agent.max_turns` (20) turns per session; turn 1 carries the full prompt, the following ones only a short continuation text (`agent_runner.ex:101-154`). Normal exit → continuation retry in 1 s; abnormal → `min(10 s × 2^(n-1), max_retry_backoff_ms = 5 min)`, with no attempt ceiling (`orchestrator.ex:13-14,1232-1243`). Tokens: deltas over absolute totals per thread (`thread/tokenUsage/updated.total`), never `last_token_usage`; summed per issue and globally, plus `seconds_running` and the last rate-limit payload (`elixir/docs/token_accounting.md`; `orchestrator.ex:1725-1797`).

**How it delivers.** The runtime writes nothing to the tracker or to GitHub. "Done" for Symphony is only "the issue left the `active_states`" (claim released, workspace kept) or "the issue entered `terminal_states`" (worker killed, workspace deleted) — reconciliation on every tick (`orchestrator.ex:421-441`). Opening a PR, commenting, moving state and merging are the agent's job, dictated by the `WORKFLOW.md` prompt and by the skills in `.codex/skills/`. In the reference flow: `Todo` → `In Progress` → PR attached, `symphony` label, green checks → `Human Review` (**not** an active state: the worker stops and the workspace stays) → a human moves it to `Merging` → the agent runs the `land` skill in a loop until `gh pr merge --squash` → `Done`; `Rework` = close the PR, delete the workpad, new branch (`elixir/WORKFLOW.md:7-11,107-116,237-263`; `.codex/skills/land/SKILL.md:11-19,97-98`). Symphony's only write of its own is the reference workflow's `before_remove` hook, `mix workspace.before_remove`, which closes open PRs from the branch when the issue reaches a terminal state without a merge (`elixir/lib/mix/tasks/workspace.before_remove.ex:43-110`).

### 1.5 Integrations

| Integration | What exists | Source |
|---|---|---|
| Linear | GraphQL, 50-item pages, `inverseRelations` for `blocked_by`, `assignee: me`; `linear_graphql` tool (raw passthrough) | `elixir/lib/symphony_elixir/linear/{client,agent_tool}.ex` |
| GitHub Issues | REST `GET /repos/{o}/{r}/issues` (`state`, `per_page=100`, `sort=created`); states only `open`/`closed`; PRs not dispatchable; `blocked_by` always `[]`; **no** GraphQL or Projects; `github_api` tool (GET/POST/PATCH/PUT/DELETE on a relative path) | `github/client.ex:105-221,344-347`, `github/adapter.ex:11-12`, `github/agent_tool.ex:8-36` |
| GitLab Issues | REST v4, states `opened`/`closed`, `dispatchable` always `true`; `gitlab_api` tool | `gitlab/{client,adapter,agent_tool}.ex` |
| Jira Cloud | `POST /rest/api/3/search/jql`, `bulkfetch`; "Blocks" links become `blocked_by`; `jira_rest` tool (path required `/rest/api/3/`) | `jira/client.ex:92-152,312-356` |
| Asana | tasks per project, state = section name; `asana_api` tool | `asana/client.ex:98-227` |
| Chat / notification | **none** (grep for slack, discord, webhook, telegram, teams, pagerduty, smtp: empty). The "notification" is the `## Codex Workpad` comment on the tracker | `elixir/WORKFLOW.md:86-87,295-329` |
| Model / provider | **Codex only** (`codex.command`, default `codex app-server`); zero mentions of `OPENAI_API_KEY`, Anthropic, Claude or Ollama; auth is the CLI's own (`~/.codex/auth.json`) | `config/schema.ex:181`, `elixir/WORKFLOW.md:34` |
| Observability | ANSI TUI always on (`status_dashboard.ex`, 1,941 lines): Agents n/max, Throughput tps + sparkline, Runtime, Tokens, Rate Limits, Running table (ID, STAGE, PID, AGE/TURN, TOKENS, SESSION, EVENT), Backoff queue. Optional web (`--port`): Phoenix LiveView with Running/Retrying/Blocked/Tokens/Runtime cards and three tables; JSON API `GET /api/v1/state`, `GET /api/v1/<issue>`, `POST /api/v1/refresh`; no authentication, host `127.0.0.1` | `router.ex:17-41`, `presenter.ex`, `dashboard_live.ex:42-328` |
| Persistence | **none**: no Repo, DB, ETS or DETS; a single rotating log `log/symphony.log` (10 MiB × 5) correlated by `issue_id`/`session_id` | `log_file.ex:9-11`, `elixir/docs/logging.md` |
| Security | tracker credentials removed from the Codex environment (`unset` + `env: false`); tools run host-side; cwd and symlinks validated; hooks are "fully trusted configuration" | `app_server.ex:192-228`, `SPEC.md` §15 |

Each adapter exposes **one** generic tool to the agent, an authenticated passthrough to the raw API: "the tool can access whatever the configured Linear token can access" and "adds no idempotency key, retry, scope guard, or rate-limit policy" (`elixir/README.md:229-235`). The protection is the credential, not Symphony.

### 1.6 What is configurable

Everything lives in the YAML front matter of `WORKFLOW.md`, typed by `elixir/lib/symphony_elixir/config/schema.ex`. Keys and defaults (selection; the complete table is in the notes):

| Block | Key | Default |
|---|---|---|
| `tracker` | `kind` (required), `endpoint`, `api_key` (`$VAR`), `project_slug`, `assignee`, `provider` (adapter map), `required_labels`, `active_states`, `terminal_states` | Linear/memory: active `Todo, In Progress`; terminal `Closed, Cancelled, Canceled, Duplicate, Done` |
| `polling` | `interval_ms` | 30,000 |
| `workspace` | `root` (accepts `~` and `$VAR`) | `<tmp>/symphony_workspaces` |
| `worker` | `ssh_hosts`, `max_concurrent_agents_per_host` | `[]`, nil |
| `agent` | `max_concurrent_agents`, `max_turns`, `max_retry_backoff_ms`, `max_concurrent_agents_by_state` | 10, 20, 300,000, `{}` |
| `codex` | `command`, `approval_policy`, `thread_sandbox`, `turn_sandbox_policy`, `turn_timeout_ms`, `read_timeout_ms`, `stall_timeout_ms` | `codex app-server`, `reject` map, `workspace-write`, `workspaceWrite` without network, 3,600,000, 5,000, 300,000 |
| `hooks` | `after_create`, `before_run`, `after_run`, `before_remove`, `timeout_ms` | nil, 60,000 |
| `observability` | `dashboard_enabled`, `refresh_ms`, `render_interval_ms` | true, 1,000, 16 |
| `server` | `port`, `host` | nil (off), `127.0.0.1` |

The file body is the prompt (Liquid, strict) with `{{ issue.* }}` and `{{ attempt }}`. Hot reload every 1 s. OpenAI's reference `WORKFLOW.md` (`elixir/WORKFLOW.md`) points at the Linear project `symphony-0c79b11b75ea`, clones `openai/symphony` in `after_create`, runs `gpt-5.5` with `model_reasoning_effort=xhigh`, `approval_policy: never`, `networkAccess: true`, 10 agents and 20 turns.

### 1.7 Installation and operation

- Source: `mise trust && mise install` → `mix setup` → `mix build` (escript `bin/symphony`) → `./bin/symphony ./WORKFLOW.md` (`elixir/README.md:67-75`).
- Binary: Burrito per platform, published on `v*` tags and on the rolling prerelease `nightly` (only on push to `main`, no scheduled rebuild); `chmod +x` and run; "still expect `codex`, `git`, and the selected tracker credentials on the target machine" (`elixir/README.md:79-104`; `.github/workflows/burrito-*.yml`).
- CLI: `symphony [--logs-root] [--port] [WORKFLOW.md]` + the mandatory acknowledgement flag, undocumented in the README.
- A single foreground process per `WORKFLOW.md` (one tracker, one project, one repo); no Dockerfile for the service, no systemd/launchd. Horizontal scale only through `worker.ssh_hosts` (the orchestrator stays single; `ssh.ex` calls the system `ssh`).
- OpenAI's dogfood operation: skills `commit`, `push` (`gh pr create` with a body validated by `mix pr_body.check`), `pull` (merge with `rerere`), `land` (loop until merge, "## Codex Review — <persona>" reviews coming from GitHub Actions, replies prefixed `[codex]`, `gh pr merge --squash`, "Do not enable auto-merge"), `linear`, `debug` (rg in the log), `release`. That Actions workflow and the `github-pr-media`/`launch-app` skills cited in `elixir/WORKFLOW.md:218` are **not in the clone** (not verified).

## 2. Project health (data from 2026-11-06)

### 2.1 Verified numbers

| Metric | Value | How |
|---|---|---|
| Repository creation | 2026-02-26 | `gh api repos/openai/symphony --jq .created_at` |
| First public commit | `fa75ec6`, 2026-03-04 (a squash: PRs #1–#24 are from 2026-02-26..03-03) | `git log --reverse` |
| Last commit / push | `be10a1b`, 2026-09-15 (52 days ago) | `git log -1`; `--jq .pushed_at` |
| Total commits | 47 | `git rev-list --count HEAD` |
| Commits per month | 03: 10 · 04: 2 · 05: 7 · 06: 4 · 07: 20 · 08: 1 · 09: 3 · 10: 0 · 11: 0 | `git log --date=format:%Y-%m` |
| Last 3 months (08-06..11-06) | 4 commits, 1 author | `git log --since --format=%an` |
| Last 6 months | 35 commits, 7 authors | same |
| Authors | 9, all OpenAI (7 `@openai.com` emails, 2 with `company: OpenAI`); 5 with more than one commit | `git shortlog -sne`; `gh api users/<login>` |
| Bus factor | Alex Kotliarskyi: 34/47 commits (72%), 91.7% of lines, 55/64 merges | `git log --author --shortstat` |
| Commits with `Co-authored-by: Codex` | 10 | `git log --format=%b` |
| Issues | **disabled** (`has_issues=false`; wiki and projects too) | `gh api ... --jq .has_issues` |
| Discussions | 51; 38 with zero comments; 16 comments in total, all from unaffiliated accounts; **0 replies from any OpenAI login** | GraphQL `discussions(first:100)` |
| PRs | 81: 64 merged, 17 closed, 0 open | `gh pr list --state all` |
| PRs by association | COLLABORATOR 51 merged / 4 closed; CONTRIBUTOR 12/6 (all `-oai`/`-openai` logins); NONE **0 merged / 7 closed** | GraphQL `authorAssociation` |
| Fork PRs | 1 (#50, OpenAI employee) | `--json isCrossRepository` |
| Median time to merge | 0.36 h (p25 0.11; p75 2.34; max 669 h) | `--json createdAt,mergedAt` |
| Median time to close without merge | 717.9 h (~30 days; max 4,576 h) | same |
| Last maintainer signal | 2026-10-21: 8 old PRs closed in bulk in 6 seconds, with no message | GraphQL `timelineItems` |
| Releases | v0.0.1 2026-07-18 · v0.0.2 2026-07-24 · v0.0.3 2026-09-15 · `nightly` 2026-09-15; 8 assets each (4 binaries + sha256) | `gh api .../releases` |
| Binary downloads | 478 / 2,335 / 3,185 / 226 (total 6,224) | `.assets[].download_count` |
| CI | 4 active workflows; last green run 2026-09-15; runs per month 07: 118 · 08: 9 · 09: 16 · 10: 0 · 11: 0 | `gh run list` |
| `main` branch protected | no | `--jq .protected` |
| Governance | **missing**: CODEOWNERS, SECURITY.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md, CHANGELOG, ROADMAP; present: LICENSE (Apache-2.0), NOTICE, PR template, `elixir/AGENTS.md` | `test -e` |
| Stars / forks / watchers | 27,958 / 2,891 / 175; still growing (5 events on 2026-11-06); recent forks ~80–105/month | `gh api repos/openai/symphony` |
| Most active forks | `JJLiebig/sympp` (936 commits ahead, push 2026-11-06, 5★), `sandsower/rondo` (409 ahead, 28★), `odysseus0/symphony` (82★, 5 ahead) — none with critical mass | `gh api .../forks?sort=stargazers` |
| Test coverage | threshold 100% **with 28 ignored modules** (Orchestrator, AgentRunner, AppServer, Workspace, all clients and the web) | `elixir/mix.exs:11-46` |

### 2.2 Reading the data

- **Cadence:** the July peak (20 commits) is the adapter and Burrito work for `v0.0.1`/`v0.0.2`; since August there are 4 commits, the last three on 2026-09-15 to close `v0.0.3`. No commits in October or November.
- **Active maintainers:** one. Alex Kotliarskyi signs 72% of the commits, 92% of the lines and 55 of the 64 merges; in the last 3 months only he committed.
- **Bug intake:** nonexistent. Issues disabled; discussions with no maintainer reply at all. Reports with a fix ready went unanswered: #107 (three security findings, 2026-07-19), #126 (app-server hanging after a cancel), #131 (camelCase rate limits in Codex 0.160), #133 (failed turns treated as complete), #134 (**`v0.0.3` fails `thread/start` with Codex 0.164/0.165**, 2026-10-26). The median maintainer response time is not computable: the set is empty.
- **External contribution:** does not happen. The 7 PRs from unaffiliated authors were closed without a merge and without a maintainer comment; 80 of the 81 PRs came from branches in the repository itself.
- **Releases and CI:** the most "product" part of the repository — binaries for four platforms, sha256, smoke test on four runners — is automation around an internal project, not a support commitment. `nightly` only runs on push, so it has been stopped since 2026-09-15 and is identical to `v0.0.3`.
- **License and dependencies:** Apache-2.0; a modern stack (Phoenix 1.8, LiveView 1.1, OTP 28) that nobody is keeping up; no SECURITY.md to report CVEs.
- **Origin:** the internal PRs carry Linear keys `MT-703`/`MT-718`, and the quoted text from OpenAI's announcement says Symphony was born "while working on an internal productivity tool". The official page (`https://openai.com/index/open-source-codex-orchestration-symphony/`) returned HTTP 403 and **was not read**; secondary sources date the post to 2026-04-28 (seven weeks after the repository opened, on 2026-03-04) and paraphrase that OpenAI "does not plan to maintain Symphony as a standalone product" and that "some teams at OpenAI saw a 500% increase in landed pull requests" — **not verified at the source**.

### 2.3 Classification

On a scale from 0 (abandoned experiment) to 10 (product with an SLA), the data place Symphony near **3**: research/experiment published as a reference, with good release automation, no support channel, no served community and dependent on one engineer staying interested. The durable value is in `SPEC.md`, the part the README itself asks you to reimplement.

## 3. Point-by-point comparison

"Ours" = `dsh-superagent` (orchestrator + executor on DeepSeek Harness; we do not change the code, only prompts and settings via the API at `127.0.0.1:3082`) + `agent-board` (this repository, agent read-only).

| Capability | Symphony | Ours | Difference that matters |
|---|---|---|---|
| **How work comes in** | Issue state in the tracker (`active_states`, `required_labels`, assignee), 30 s polling (5 s at OpenAI); moving the card triggers it | A mention of `@sallaumen-agent` by someone on the list, read by notification polling every 60 s (`dsh: src/sources/github-trigger.ts:60-87`, `src/sources/github.ts:25`); the board creates the issue with the mention in the body (`lib/agent_board/board.ex:252-280`); editing the issue does not trigger it | In Symphony the tracker is the control plane; in ours it is the sentence. In practice the board already plays the control-plane role by opening the issue with the mention. Intake latency is higher on ours (60 s). |
| **Trackers** | Linear, GitHub Issues, GitLab, Jira, Asana (plus `memory`) | GitHub.com (no GHES, no GitHub App) and Feishu off (`dsh: docs/006-deployment.md`) | Irrelevant today: we operate one repository on GitHub. |
| **Agent / model** | **Codex only** (`codex app-server`); model via a Codex flag (`gpt-5.5`, `xhigh`) | Model per role (`eval.model`, `executor.model`) resolved by the DSH; today DeepSeek (`dsh: src/policy.ts:70-96`; `docs/agent/setup.md` §3) | **The migration blocker.** Symphony requires Codex/OpenAI; swapping the agent means rewriting `Codex.AppServer`. |
| **Internal lifecycle** | `Unclaimed → Claimed → Running → RetryQueued → Released` (SPEC §7); attempt phases; tracker state is the truth | Decision `accept|stop|ignore|unavailable`; Assignment `pending|running|ended`; Report `progress|waiting|ready|blocked|failed|dropped`; outcome `completed|merged|closed|dropped|stopped` (`dsh: src/core/model.ts:211-285`); board `queued running question ready blocked done closed stopped archived` (`lib/agent_board/board/task.ex:10`) | Our model is richer (reports, outcomes), but the board derives `question`/`ready` by a text heuristic ("?" in the summary) (`lib/agent_board/sync.ex`, commit `0405c41`). |
| **Isolation** | Workspace per issue under `workspace.root`, sanitized key, hooks, symlink validation; reused across runs | Worktree per ticket created by the *prepare command* (`git worktree add -b agent/<name>`), 10 min, under `~/.dsh/state/superagent/work/` (`dsh: src/executor/dsh.ts:28,57`; `docs/agent/how-it-works.md`) | Equivalent. Neither is a security boundary (`danger-full-access` on ours; `approval_policy: never` + network on theirs). |
| **Cleanup** | Terminal state → worker killed and workspace deleted; sweep at startup; `before_remove` hook closes orphan PRs (`workspace.before_remove.ex`) | None: "Nothing deletes old records yet, so these grow without bound" (`dsh: docs/007-architecture.md`); worktrees stay | **Our gap.** Easy to close with a script. |
| **Concurrency** | `max_concurrent_agents` 10, per-state ceiling, per-SSH-host ceiling, remote hosts | `executor.maxWorkers` default 3 (1..16) + 1 slot for a human message (`dsh: src/policy.ts:93`); today we run one worker by Lucas's decision, to measure throughput before parallelizing (live value outside the repositories: not verified) | When we parallelize, Symphony's per-state and per-host ceilings are good references; the DSH already has the knob. |
| **Gates** | None at the host level; `before_run` could run one, but the reference flow trusts the prompt ("green checks" before `Human Review`) | None at the host level; the policy requires `mix precommit` on the head and self-reporting; the board **infers** `CI local ok/falhou/?` from the report text (`lib/agent_board/local_ci.ex:497-608`) | Same weakness. Symphony has a seam (`before_run`/`after_run`) that the DSH does not. |
| **Policy and prompts** | `WORKFLOW.md` **versioned in the repository**, front matter + Liquid prompt, hot reload, validated at boot | Three sections (Communication, Ticket scope, Delivery requirements) saved by `PUT /orchestrator/api/prompts` with `baseRevision`, immutable versions, **outside git** (`dsh: docs/004-prompts.md`; `docs/agent/setup.md` §8) | **Idea #1.** Our policy lives in a SQLite, with no diff and no revision; the literal active text is not even verifiable from this repository. |
| **Delivery and merge** | The agent opens a PR (`gh`), moves it to `Human Review` (a handoff state outside the active ones); a human moves it to `Merging`; the agent squash-merges through the `land` skill | The agent opens a PR and, since 2026-11-07 UTC, merges its own PR with `gh pr merge --merge --match-head-commit <sha>` when `mix precommit` passed, no review asks for changes and `mergeable == MERGEABLE`; no branch protection; "GitHub Actions is never a reason to wait" (`docs/agent/setup.md` §8, commit `bd4ffd1`) | Symphony implements the human gate **by excluding a state from the `active_states`**, without code. We chose not to have a gate; if we ever want one, a handoff label gives the same effect. |
| **Human in the loop** | In-memory `blocked` map when Codex asks for approval/input; a single `## Codex Workpad` comment (Plan, Acceptance Criteria, Validation, Notes, Confusions); **no notification** | Report `waiting` + `human_action`; `person/*` stage; board "Precisa de você" (Needs you) (`blocked ++ review ++ question`, `lib/agent_board/lanes.ex`) and **voice** (`lib/agent_board/announcer.ex`, commit `87511a9`) | We are ahead at calling the owner. Their workpad is better for **reading** state: a fixed structure, not a "?" in the text. **Idea #2.** |
| **Retries, stall, timeouts** | Continuation 1 s; backoff 10 s·2ⁿ ≤ 5 min with no ceiling; stall 5 min without an event → kill and reschedule; silence 1 h per turn; `max_turns` 20; reconciliation on every tick (issue closed mid-run → stop) | Launch 3 transient attempts (5 s→300 s); turn 15/30/60 s; `failed` is **not** retried on its own — it waits for a human Retry (`dsh: docs/003-execution.md`); no stall detection per event; the board has `agent_running_ttl` freshness of 2 min (`lib/agent_board/freshness.ex`) | Symphony recovers on its own from transient failures and stuck workers; ours stops and waits. **Idea #5** (stall visible on the board). |
| **Tokens and cost** | Per issue and global (in/out/total), runtime, rate limits — in memory, in the TUI and in the API | Executor: **nothing** per ticket (`dsh: docs/007-architecture.md`); board: `ai_calls` with tokens, `cost_micros`, a daily ceiling of 5 M, only for the board's own calls (`lib/agent_board/ai/call.ex`) | **Our gap.** We do not know what a ticket costs. It depends on the DSH exposing usage (to investigate). |
| **Observability** | TUI + LiveView + JSON: running/retrying/blocked, tokens, turns, last humanized event, backoff queue; **no history** | DSH panel (Overview, Source, Trigger, Eval, Execution, Settings); board with lanes, the "real step" read from the worktree (`lib/agent_board/agent_worktree.ex`), freshness, `events`, LiveDashboard, API without auth; `status.sh`/`tickets.sh`/`counts.sh`/`logs.sh` | They have better per-run telemetry (tokens, turn, last event); we have history, freshness and GitHub context. |
| **Persistence** | None; a restart loses retries and blocks | Agent SQLite (source) + board Postgres (`repositories, tasks, pull_requests, reviews, events, comments, ai_calls, settings`) | Our decisive advantage for metrics and audit. |
| **Metrics** | Throughput in tokens/s + sparkline; runtime; nothing about PRs or throughput | `MergeTrend` 7 d, `Lanes.merge_log`, a digest since the last visit, the DSH's 24 h `flow`; an hourly panel under construction in the sibling session; **nobody computes cycle time** | Neither measures throughput per hour or cycle time per ticket; the data for that exists only on our side (`assignments[].startedAt`, `pull_requests.merged_at`, `tasks.started_at/state_changed_at`). |
| **Spec and tests** | Normative `SPEC.md` (18 sections, pseudocode, test matrix, conformance checklist); 15 k lines of ExUnit over real OTP with a fake app-server | Binding `docs/maintainer-contract.md`, ADRs, `PIPELINES.md`, Elixir Agent Kit; DSH with 9 numbered docs and 59 specs; board with 46 test files | The SPEC is Symphony's best piece: it serves as a **checklist** to audit our cycle (reconciliation, restart, stale dispatch). **Idea #3.** |
| **Secrets** | Tracker tokens outside the child environment; host-side tools | `GH_TOKEN`/`GITHUB_TOKEN` removed; `gh` shim in `worker-bin`; the agent's credential helper (`dsh: docs/006-deployment.md`) | Equivalent. |
| **Packaging and service** | Escript or Burrito binary in the foreground; no service | DSH in tmux (`scripts/dsh-superagent`), board in launchd on 4099 (`ops/com.agentboard.plist`) | Nothing to bring. |
| **Project health** | 1 maintainer, 52 days idle, no intake, self-declared prototype | Us: daily commits; DSH: research prototype "not production-ready" (`dsh: README.md`), one commit in our clone | Both prototypes; ours is alive and under our control. |

## 4. Recommendation

### 4.1 Migrate?

**No.**

- **Cost:** swap DeepSeek for Codex (an OpenAI subscription/API and dependence on the CLI version, which `v0.0.3` no longer tracks according to #134); rewrite the board's reading (today the agent's SQLite; on Symphony there would only be an in-memory `GET /api/v1/state`); reproduce mention-based intake (Symphony reads issue state, not comments); rewrite the merge policy as `WORKFLOW.md`; abandon `tickets.sh`/`counts.sh`/`status.sh`.
- **What we would lose:** persistent history (SQLite + Postgres), the report model (`waiting`/`ready`/`blocked`/`human_action`) that "Precisa de você" and the voice depend on, human Retry with branch and PR reuse, the Eval allowlist, provider independence, and Lucas's ability to edit the policy through the API without restarting.
- **What we would gain:** parallelism with per-state and per-host ceilings, SSH workers, robust reconciliation (an issue closed mid-run stops the agent), automatic retries and stall detection, tokens and rate limits per run, hot `WORKFLOW.md`, five trackers.
- **Abandonment risk:** high. One maintainer, zero public replies, a self-declared prototype and an explicit recommendation to "implement your own hardened version".

### 4.2 Adopt pieces

Yes, the design ones. None requires Symphony code; all fit in prompts, scripts and the board:

1. Policy and prompt as a file versioned in this repository, with a script that does `get`, `diff` and `put` against the orchestrator API (what `WORKFLOW.md` + hot reload give them).
2. "Workpad": a structured comment per issue, with fixed sections, that the board reads instead of guessing from a "?".
3. `SPEC.md` §7, §8 and §14 as a checklist to audit the DSH lifecycle and record the result in the contract.
4. Cleanup in terminal state: remove worktrees of ended tickets and close orphan PRs (equivalent to `before_remove`).
5. Stall and per-run telemetry on the card: "no signal for N min", turns and, if the DSH exposes them, tokens.

### 4.3 Just learn

Already done with this document: the "handoff state outside `active_states`" model as a human gate without code; the ordering priority → age → identifier; revalidation by id before dispatching; token accounting over absolute totals (never over reported deltas); the separation of reading (orchestrator) × writing (agent via a tool with a host-side credential).

### 4.4 Ideas to bring, by priority

Effort: **P** ≤ half a day · **M** 1–2 days · **G** > 2 days. Value: what changes for Lucas operating the platform.

| # | Idea | In Symphony | Where it would land here | Effort | Value |
|---|---|---|---|---|---|
| 1 | **Policy versioned in a file + sync with the API** | `WORKFLOW.md` in the repo, validated at boot, hot reload (`workflow_store.ex`) | `docs/agent/prompts/{communication,scope,delivery}.md` + `scripts/agent/prompts.sh get|diff|put` using `GET/PUT /orchestrator/api/prompts` with `baseRevision`; `docs/agent/setup.md` §8 starts pointing at the file | M | High: the merge policy becomes text reviewable in a PR; the "not verified" about the active text goes away; the classifier that blocked the `PUT` stops being a problem (script with the body in a file). |
| 2 | **Workpad: a structured comment per issue** | `## Codex Workpad` with Plan / Acceptance Criteria / Validation / Notes / Confusions, edited in place (`elixir/WORKFLOW.md:295-329`) | Communication section of the prompt (via idea 1) + a parser in the board (`lib/agent_board/board.ex` `agent_asked?`, `lib/agent_board/local_ci.ex`) reading fixed sections: Pergunta, Validação (`mix precommit` + sha), Bloqueio | M | High: less comment noise; `question`/`blocked`/`CI local` start being read from fields, not from "?" and sentences. |
| 3 | **Lifecycle audit against the SPEC** | `SPEC.md` §7 (states), §8 (tick, reconciliation, stale dispatch), §14 (failures, restart), §18 (checklist) | ADR `docs/decisions/0003-ciclo-de-vida-do-agente.md`: what the DSH does when the issue is closed during the run, when it restarts with a `running` ticket, when the mention arrives twice; what the board must show in each case | M | High: today nobody can answer these three questions; that is what will hurt most when we parallelize. |
| 4 | **Cleanup of worktrees and orphan PRs** | Terminal → `rm -rf` of the workspace; sweep at startup; `mix workspace.before_remove` closes unmerged PRs | `scripts/agent/cleanup.sh`: lists `ended` tickets in SQLite, `git worktree remove` + `prune`, closes open PRs from `agent/*` branches whose ticket ended without a merge; `--dry-run` by default | P/M | Medium: disk and PR list clean; prevents a stale branch from being picked up by mistake. |
| 5 | **Stall visible on the card** | `stall_timeout_ms` 5 min without an event → restart; the TUI shows AGE/TURN and the last event | Board: "no signal for N min" from `report.at`/`idleAt` in SQLite and the worktree mtime; above a threshold it becomes an item in "Precisa de você" with Retry/Stop actions (`lib/agent_board/lanes.ex`, `lib/agent_board/freshness.ex`) | M | Medium/high with a single worker: a stuck ticket today blocks the whole queue in silence. |
| 6 | **Tokens and cost per ticket** | `codex_totals` per issue (`orchestrator.ex:1725-1797`), rate limits | Spike: find out whether the DSH records usage per Session (logs in `.artifacts/`, health `models`); if so, a column on the card and a sum in `ai_calls`-like | P (spike) → G | High if possible; today the executor cost is invisible. |
| 7 | **Dispatch ordering and revalidation** | priority → `created_at` → id; refetch by id before launching | When `maxWorkers` > 1: ask the DSH (settings/prompt) for age order; the board already shows the queue in order — document the rule | P | Low now, medium when parallelizing. |
| 8 | **Optional handoff state** | `Human Review` outside the `active_states` = human gate without code | Label `needs-owner` that the policy respects (do not merge) and the board shows in "Precisa de você" | P | Low: Lucas decided not to review; it stays as an option for sensitive tickets. |
| 9 | **Per-task JSON endpoint** | `GET /api/v1/<issue>` with workspace, attempts, last error | `GET /api/tasks/:id` on the board with worktree, report, local gate, PR | P | Low: a convenience for scripts. |

## 5. Plan for the next parallel front

> **Status (2026-11-08):** the five points were delivered — versioned prompts
> ([`prompts/`](../agent/prompts/communication.md) + `scripts/agent/prompts.sh`,
> see [setup §8](../agent/setup.md#8-merge-policy)), workpad
> ([contract](../maintainer-contract.md#workpad)),
> [ADR 0003](../decisions/0003-ciclo-de-vida-do-agente.md),
> `scripts/agent/cleanup.sh` ([how-it-works](../agent/how-it-works.md)) and the
> visible stall ([contract — Silence](../maintainer-contract.md#silence)).

Five points, each the size of an issue/PR, independent of each other and of the sibling session (metrics per hour). None changes `dsh-superagent`; two change prompts through the API, three change this repository.

1. **Versioned policy and sync script (idea 1).** Create `docs/agent/prompts/` with the three sections and `scripts/agent/prompts.sh` (`get` writes the files; `diff` compares with the API; `put` sends with a `baseRevision` read from `get`). Update `docs/agent/setup.md` §8 and the scripts table in `AGENTS.md`. Done when `prompts.sh diff` comes out clean against the active revision and the literal text of the Delivery requirements is in git. Gate: `mix format --check-formatted` and `shellcheck` on the scripts.
2. **Workpad in the prompt and on the board (idea 2).** PR A (prompt, via `prompts.sh put`): the Communication section asks for a single `## Relatório do agente` comment with `### Plano`, `### Validação` (command, result, sha), `### Pergunta` (empty or one question), `### Bloqueio`. PR B (board): `AgentBoard.Workpad.parse/1` + `Board.agent_asked?` and `LocalCI` starting to prefer the workpad when it exists, with a fallback to the current heuristic; tests with fixtures for both formats. Done when a ticket with a workpad shows as `question` without a "?" in the summary and `CI local` comes from the Validação field.
3. **Lifecycle ADR (idea 3).** Read `dsh: src/core/tickets.ts`, `src/executor/dsh.ts` and `src/sources/github.ts` with SPEC §7/§8/§14 alongside and answer, with a citation: issue closed on GitHub during the run; DSH restart with a `running` Assignment; second mention on the same issue; PR closed without a merge. Record in `docs/decisions/0003-ciclo-de-vida-do-agente.md` the observed behavior, what the board shows today and what it should show. Done when each question has a cited answer or "not verified" with the experiment that is missing.
4. **Cleanup of worktrees and orphan PRs (idea 4).** `scripts/agent/cleanup.sh` with `--dry-run` by default, `--apply` to execute; reads `ended` tickets in SQLite (the same query as `tickets.sh`), removes the matching worktree under `~/.dsh/state/superagent/work/`, runs `git worktree prune`, and closes with a comment the open PRs from branch `agent/<name>` whose outcome is `closed|dropped|stopped`. A line in `AGENTS.md` and in `docs/agent/how-it-works.md`. Done when `--dry-run` lists exactly what `tickets.sh` shows as ended and nothing more.
5. **Visible stall (idea 5).** On the board, compute `last_signal_at` per `running` ticket = max(`report.at`, `idleAt`, worktree mtime) and expose `stalled_for` on the card; above `:stall_after_ms` (default 15 min) the ticket enters "Precisa de você" with `why` "Sem sinal há N min" and Retry (DSH API) / Stop actions. Contract in `docs/maintainer-contract.md` (it is derived, never written to SQLite; one sentence per state change in the voice). Done when a stuck ticket shows up within one poller cycle (10 s) after the threshold. Coordinate with the metrics session so as not to duplicate `last_signal_at`.

Side finding from the research, for a separate issue: `scripts/agent/tickets.sh` and `counts.sh` read `assignments[0]` (the first Assignment), while `AgentBoard.AgentState.normalize/1` uses the last one; after a Retry the scripts show the old report (`lib/agent_board/agent_state.ex:191-231`).

## 6. Not verified

- The text and date of OpenAI's official announcement (HTTP 403); the phrases "500% more PRs" and "does not intend to maintain it as a product" are third-party paraphrases.
- Star timeline (the `stargazers` endpoint with `star+json` returned 404/401); the peak was estimated from forks and discussions (100 forks in 48 h starting 2026-03-04).
- Collaborators with push (403) and the affiliation of 6 of the 9 authors (only the commit email and the login convention).
- Codex CLI versions compatible with `v0.0.3`; the incompatibility report (#134) was not reproduced.
- Whether Symphony's tests pass: nothing from the clone was executed.
- The Actions workflow that generates "## Codex Review — <persona>" and the `github-pr-media`/`launch-app` skills cited in `WORKFLOW.md` are not in the clone.
- On our side: the literal text of the Delivery requirements active in the orchestrator, the live value of `executor.maxWorkers` and of the per-role model, and our installation's `executor.prepare` live outside the two repositories.
- Whether the DSH records tokens per Session anywhere (the basis of idea 6).

## 7. How to reproduce

```sh
# read-only clone in its own directory; do not run anything from it
git clone https://github.com/openai/symphony /isolated/path/symphony
C=/caminho/isolado/symphony
git -C $C log --format='%ad' --date=format:%Y-%m | sort | uniq -c
git -C $C shortlog -sne HEAD
git -C $C log --since=2026-08-06 --format='%an' | sort | uniq -c
gh api repos/openai/symphony --jq '{created_at,pushed_at,stargazers_count,forks_count,has_issues,license:.license.spdx_id}'
gh pr list --repo openai/symphony --state all --limit 500 --json state --jq '.[].state' | sort | uniq -c
gh api graphql -f query='{repository(owner:"openai",name:"symphony"){discussions(first:100){totalCount nodes{number comments{totalCount}}}}}'
gh run list --repo openai/symphony --limit 100 --json name,conclusion,createdAt
gh api repos/openai/symphony/releases --jq '.[] | "\(.tag_name) \(.published_at) \([.assets[]|.download_count]|add)"'
```

The research notes carry the 51 numbers with the exact command for each, the complete configuration schema table and the cited inventory of our platform.
