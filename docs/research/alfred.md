# Alfred × our platform: product plan

- **Analysis date:** 2026-11-07.
- **Subject:** the "Alfred" specification (version 1.2, October 2026), which a colleague wrote so an AI could build, phase by phase, a personal assistant on the person's computer. It is third-party text: we read a local copy outside the repository; here there is only paraphrase and short quoted excerpts.
- **Our platform:** the board (this repository), the `dsh-superagent` executor (DeepSeek Harness, prefix `dsh:` in citations, root at `/Users/tavano/Documents/deepseek-harness/default-workspace/dsh-superagent-prototype`) and direct use of Claude Code and Codex outside the board.
- **Owner's goal:** one day to work only by creating tasks on the board, without opening DeepSeek, Claude or Codex, with the board deciding where each task goes.
- **Method:** reading the board and the prototype with file and line citations; read-only spikes on local usage files from the three tools (structure and numbers, never conversation content); CLI `--help`. No paid calls were made. Elixir Agent Kit workflow: `ai-orchestration` (the risk is assigning work and cost to the right executor), in analysis mode: this PR only adds documentation.
- **Out of scope:** the Telegram channel. The owner decided on 2026-11-07 to leave it for later; section 5 says what that postpones.
- **Research notes** (commands and spike output): session notes folder, `alfred-usage-spike.md` and `alfred-dsh-api.md`. This document is the distilled version.

## Summary

**Do not adopt Alfred as a base. Take six ideas from it and follow a four-step path to the owner's goal: the board sees the three tools, suggests where each task goes, dispatches, and only then decides on its own, by category, where it has already proven to choose well.**

Three facts decide:

1. **Most of the work is outside the board.** In the last 7 days there were 120 Claude Code sessions across 11 repositories and 44 Codex threads across 5; the board's executor ran 33 tickets in total, all in the single repository the orchestrator watches (`sallaumen/arena-rogue`). The board shows two repositories and one executor.
2. **DSH does not route per task.** The model is global per role and the executor is fixed in the runtime (`dsh:src/policy.ts:91-97`, `dsh:src/app/runtime.ts:68`); the orchestrator API does not create tickets. The routing decision has to live in the board, before the executor.
3. **The three tools leave usage readable in local files, without a paid call, but in different currencies.** DeepSeek spends account balance (US$ estimated by the board's table), Claude Code runs on the Max subscription (the US$ it calculates is list price, not an invoice), and Codex on the ChatGPT plan (only the weekly quota percentage is available). The visualization and the router show each in its own currency and never add the three together.

The Alfred ideas that come in: the **risk gate in code**, with a confirmation that states the actual values (F2.3); the **trust ladder**, here applied to executor choice: suggest, confirm, automatic per category after 10 correct choices, never rising on its own (F2.4, F4.1); the **visible cost at every choice** (F1.5, F2.4); the **day summary with a wall clock** (F1.6); the **approved facts** as preference memory (F4.2); and **delegation to Claude Code as a confirmed action**, with the board owning the risk decision (F3.0–F3.3). The rest of Alfred (its own engine, channels, automations the assistant writes for itself, screen control) does not come in; section 5 says why.

**The first three workstreams**, which can start today in parallel:

1. **See Claude Code and Codex** (F1.1 and F1.2, then F1.3): read-only usage readers and the usage ledger. Needs nothing from the owner.
2. **Action registry with risk** (F2.3): the single gate, a prerequisite for any dispatch that spends. Needs nothing from the owner.
3. **ADR 0004 for the dispatch boundary** (F3.0): write the decision and collect D1, D2, D3 and D5 from the owner while the first two proceed.

## 1. What Alfred is

It is not software: it is a briefing for an AI to install, with the person's own API key, a local assistant in Python (FastAPI, SQLite, system vault). The design has five organs (ear, brain, hands, memory, voice and screen) and one rule: every action of the hands has a risk — green (read-only), yellow (changes something reversible) or red (deletes, sends outside, spends money) — and "the code enforces this, not the prompt". On top of that come four levels of autonomy that rise only after a gate, memory in three layers, wall-clock routines, per-task model routing with visible cost, transparency for every tool call, a background objective, automations, connectors, supervision of a worker with a report and audit, and delegation of programming to Claude Code as a red action.

What it solves is different from what we solve. Alfred is a general assistant for a layperson; our board is a control panel for code agents for a developer, who already has history in Postgres, GitHub as a trail, and an autonomous executor that opens and merges its own PRs. So the comparison below does not ask "migrate?", but "which piece of Alfred is missing for the board to decide and dispatch on its own?". The earlier analysis of Alfred, done for another owner project, reached the same reading: that project's safety base was already ahead, and Alfred's value lies in the trust and learning layer above the gate.

## 2. Point-by-point comparison

Verdict: **bring in** (the idea enters almost as is), **adapt** (it enters in another form) or **do not bring in**. The number in brackets points to the plan item (section 4).

### 2.1 Task management

| Topic | Alfred | Today in the board and the agent | Verdict |
|---|---|---|---|
| **Background objective** | Accepts an objective, breaks it into steps, records progress in a file, notifies on completion or a stall; yellow and red steps wait for the person | The composer refines the request and splits it into tasks that close on their own (`lib/agent_board/intake.ex`, two calls on the fast tier); each task becomes an issue with the agent mention (`lib/agent_board/board.ex:253`, `lib/agent_board_web/live/board_live.ex:2062`); each task's progress is the workpad (`## Relatório do agente`, the "Agent report" workpad heading, `lib/agent_board/workpad.ex`); a task born from another stores `origin_task_id` (`lib/agent_board/board/task.ex:25`). The objective does not exist as a thing: the board does not know that five tasks are one request or when the request finished | **Adapt** [F3.4]: the objective is a group of tasks with a done criterion, and progress is computed from the tasks, never written by hand |
| **Queue** | Command queue that survives the computer being turned off | Board queue (`Lanes.queue/3`, `lib/agent_board/lanes.ex`) and runner queue (`load.queued`, `lib/agent_board/orchestrator.ex`) | **Do not bring in**: it already exists and is persistent on both sides |
| **Resume** | Restarting does not lose a command; at most three attempts with increasing backoff | Automatic retry for transient failure at 1, 5 and 15 min, one per Assignment (`lib/agent_board/auto_retry.ex`, contract "Automatic retry"); "Tentar de novo" ("Try again") and "Religar o agente" ("Restart the agent") confirmed (`lib/agent_board/agent_control.ex`); what DSH does on restart is in ADR 0003 | **Do not bring in**: we are ahead; the same rule applies to new executors [F3.5] |
| **Autonomy by levels** | Four levels (answers, acts when asked, warns and acts within authorization, orchestrates) and switchable modes (observe, supervised, released); rises only after a gate; after 10 correct choices in a row offers to make it automatic, never rises on its own | Implicit and spread out: the executor merges its own PRs based on prompt text (`docs/agent/setup.md` §8); automatic retry is turned on and off by a variable (`AGENT_BOARD_AUTO_RETRY`); voice creates directly only when the owner says "cria direto" ("create directly") (contract, "The voice"). No screen says at what level each thing operates | **Bring in** as a router mode [F2.4, F4.1]: *suggest* (the owner chooses), *confirm* (the board chooses and the owner approves), *automatic* (per category, offered after N correct choices, revoked on the first error) |
| **Risk gate in code** | Every tool declares risk; red always confirms with the actual values; confirmation comes from the person, never the model; refusal is recorded | Confirmations exist, but per entry point: the `AgentAction` component does not act on the first click (`lib/agent_board_web/live/board_components/agent_action.ex:1-14`); the voice conversation turns a write into a proposal that only the spoken "sim" ("yes") executes (`lib/agent_board/conversation.ex:95-127`); the command catalog marks `local`, `read`, `confirm` and `direct` (`lib/agent_board/voice/commands.ex`). The JSON API creates, stops and archives without confirmation (`lib/agent_board_web/controllers/board_controller.ex:38-73`), acceptable today because the service only listens on `127.0.0.1:4099` (observed with `lsof`; `config/dev.exs:23`). There is no single catalog of actions with risk | **Bring in** [F2.3]: an action registry for the board (create, ask, stop, archive, retry, restart, change the ceiling, dispatch to a paid executor) with risk, a confirmation sentence with the actual values and a record of the decision; UI, voice and API go through it. Dispatching to Claude or Codex is yellow or red because it spends |
| **Spending ceiling** | Daily and per-task ceiling; timeout per task | Daily ceiling of 5 M tokens only for the board's own calls (`lib/agent_board/ai/budget.ex:15`), checked before the network; daily character ceiling for ElevenLabs; no ceiling on the executor | **Bring in** [F2.4, F3.3]: per-task and per-day ceiling on each executor, visible before dispatch |
| **Stop button** | "Para tudo" ("Stop everything") interrupts | "Parar" ("Stop") per task closes the issue (`Board.stop_task/2`, `lib/agent_board/board.ex:354`); there is no global dispatch pause | **Bring in** [F3.3]: "pausar despacho" ("pause dispatch") for the router; what is already running continues, nothing new leaves |

### 2.2 Communication

| Topic | Alfred | Today | Verdict |
|---|---|---|---|
| **Fluency and short messages** | Short answers, in voice at most two sentences; repeat what it understood before anything red; say "não tenho certeza" ("I'm not sure") | Voice speaks at most two sentences per update (`lib/agent_board/announcer.ex:25`), free replies speak the first sentence (`voice_replies` = `short`), every sentence comes from `AgentBoard.Voice.Phrases`, and voice lookup answers only with board facts (`lib/agent_board/conversation/lookup.ex`) | **Do not bring in**: it is already the rule |
| **Confirmation with the actual values** | The confirmation sentence carries the values ("apagar a pasta X" — "delete folder X"), not "confirma?" ("confirm?") | `AgentAction` shows what will happen; the voice proposal names the task and the question | **Adapt** [F2.3, F2.4]: the confirmation of a paid dispatch says executor, repository, ceiling and estimated cost ("Mandar #412 para o Claude Code no arena-rogue, teto US$ 3, estimativa US$ 0,80?" — "Send #412 to Claude Code in arena-rogue, ceiling US$ 3, estimate US$ 0.80?") |
| **Reports** | Daily report of what the worker did; 10-minute weekly review; "what did you do today?" read from an append-only log | One-sentence digest since the last visit (`Lanes.digest/3`, `lib/agent_board/lanes.ex`), seven days of merges (`lanes.ex`), the hourly throughput strip (contract, "Throughput"), activity (`Board.events/2`, `board.ex:735`), the spoken "status". Nothing joins the day by executor and by cost; what the board did on its own (retries) is in events, without a summary | **Bring in** [F1.6, F4.3]: the "Resumo do dia" ("Day summary") (done, spent, failures, what the board did on its own) and the weekly review with suggestions the owner approves or rejects |
| **Alerts only on state change** | The watcher reports the change, not the state; hourly alert limit | The `Announcer` is a pure diff between the previous board and the current one, calls once when a task enters question, block or review, and stays silent while it remains there (`announcer.ex:1-20`; contract, "Silence") | **Do not bring in** now; the hourly limit only matters when there is a channel outside the browser |

### 2.3 Menus and navigation

| Topic | Alfred | Today | Verdict |
|---|---|---|---|
| **A single control center** | One process receives text, voice, channels and the scheduler; panel, terminal and phone are only screens | The board is that center for the DSH executor: one page with the repository rail (`repo_rail.ex`), panels per URL (`@panels`, `lib/agent_board_web/live/board_navigation.ex:9`) and settings behind a disclosure (`settings_menu.ex`). But it only sees two repositories (`sallaumen/arena-rogue` and `sallaumen/o_colmex`, `GET /api/repos`) and one executor; work done directly in Claude Code and Codex is invisible | **Adapt** [F1.5, F1.7, F2.1]: the board starts seeing the three tools and all repositories the owner works in |
| **A view of the day, not the repository** | The home screen is the assistant, not a folder | Navigation is by repository; `Overview.repo_overview/0` (`board.ex:778`) already counts tasks by state across all of them, but only feeds the rail markers | **Bring in** [F2.1]: a "Hoje" ("Today") view with what needs the owner, what is running and where, and the spend, across all repositories |
| **"O que você consegue fazer?" ("What can you do?") and `/uso`** | Capability catalog and a command with session tokens and cost | "O que posso pedir" ("What can I ask for") (`AgentBoard.Voice.Commands`) and the AI panel with engine, model, tokens and estimated cost of each board call (`lib/agent_board_web/live/board_components/ai.ex`) | **Adapt** [F1.5]: the spend panel gains the executors, not only board calls |

### 2.4 Memory

| Topic | Alfred | Today | Verdict |
|---|---|---|---|
| **Live context** | Conversation context, compacted near 60% of the window | The voice conversation stores turns in `voice_turns` and folds older ones into a summary (`lib/agent_board/conversation.ex:46-70`, call `:summarize_conversation`) | **Do not bring in**: it exists |
| **Complete journal for lookup** | Everything that was said, with accent-insensitive search | Issues, comments, events, `ai_calls` and runner reports are already the journal; voice lookup reads part of it | **Do not bring in**; textual search only if a real case asks for it |
| **Short, durable, approved facts** | A nightly routine proposes new facts and the person approves; view, correct, forget | Does not exist in the board. For code, durable facts are already `AGENTS.md`, the contract and the Elixir Agent Kit in each repository | **Adapt** [F4.2]: routing and preference facts ("no o_colmex, tarefas de UI vão para o Claude" — "in o_colmex, UI tasks go to Claude"), proposed by the board from history and approved by the owner; never facts about code, which remain in the repositories |
| **Skills as files that grow** | After three repetitions, offer the skill and show the file before saving | The kit and versioned prompts (`docs/agent/prompts/`, `scripts/agent/prompts.sh`) already do this with PR review | **Do not bring in** |

### 2.5 Routines

| Topic | Alfred | Today | Verdict |
|---|---|---|---|
| **Wall clock** | A delayed reminder fires after the computer slept; never a sleep timer | The only schedule is sync every 5 min (`config/config.exs:64-72`). `Oban.Cron` 2.24.2 only inserts a job when the expression matches the minute in which it evaluates (`deps/oban/lib/oban/cron.ex:344`): a missed time with the Mac asleep is not recovered. For sync this does not matter; for an 8 a.m. summary it does | **Bring in** as a rule [F1.6]: a daily routine is "has today's run already happened after 8 a.m.?", checked on every tick, with the execution recorded once per day |
| **Scheduled tasks in observe mode** | Good morning, reports and monitoring, read-only by default | None | **Bring in** [F1.6]: the morning summary on the board and in voice, read-only, without a model by default |
| **Automations the assistant creates** | Triggers, chaining, mini-apps, connectors | — | **Do not bring in** (section 5) |

### 2.6 Transparency and supervision

| Topic | Alfred | Today | Verdict |
|---|---|---|---|
| **Every call visible, with cost** | Name, arguments and result of each tool on one line; which model answered and how much it cost | Each board call is a row in `ai_calls` (`lib/agent_board/ai/call.ex`); executor spend per task comes from DSH transcripts (`lib/agent_board/executor_usage.ex`, section "Executor do agente" in the inspector, `inspector.ex:351-400`); voice has "Bastidores da voz" ("Voice backstage") | **Adapt** [F1.1, F1.2, F1.5]: the same reading for Claude Code and Codex, with counts and cost, never conversation content |
| **Supervisor with report and audit** | A read-only supervisor checks the work against written rules, shows the excerpt and the violated rule, suggests, and the person approves | The board checks the local gate against the PR sha (`lib/agent_board/local_ci.ex`, contract "Workpad") and explains each failure (`lib/agent_board/agent_block.ex`) | **Adapt** [F4.3]: the same delivery check for Claude and Codex PRs (gate on head, `Closes #n`, merge by the right owner), and the owner's correction becomes an example for the router |
| **Delegate to Claude Code** | Red action; Alfred remains the owner of the risk decision; Claude can ask Alfred over MCP | Does not exist: only DSH executes | **Bring in** [F3.1–F3.3]: this is section 3 |
| **Simulation before the real thing** | Simulation mode in actions | `AI_REHEARSAL` answers board calls with fixtures; nothing similar for the executor | **Adapt** [F2.4]: the *suggest* mode is the router's simulation: it decides, records and does not dispatch |

## 3. Routing between DeepSeek, Claude and Codex

### 3.1 Where the work is today

Count for the last 7 days from local files (2026-11-07 spike, notes `alfred-usage-spike.md`):

| Tool | Volume | Repositories |
|---|---|---|
| Claude Code | 120 sessions (plus 867 subagent files) in 88 directories | 11, led by forrozin-page (31), o_colmex (29), pokex (26) and agent-board (12) |
| Codex | 44 threads in 7 directories | 5: agent-board (14), o_colmex (13), forrozin_page (10), mtg-deck-magician-skill (5), deckex (1) |
| DeepSeek through the board (`dsh-superagent`) | 33 tickets **in total**, all closed (30 merged, 2 completed, 1 stopped) | 1: `sallaumen/arena-rogue`, the only one the orchestrator watches (`dsh:src/deployment.ts:44-54`; one repository per orchestrator, `dsh:README.md:7`) |

The board shows two repositories (`arena-rogue` and `o_colmex`) and one executor. Most of the owner's work happens where the board does not look.

### 3.2 How each executor is triggered without opening the tool

| Executor | Today | Programmatic trigger | Model | Verified |
|---|---|---|---|---|
| **DeepSeek** (`dsh-superagent`) | A comment with `@sallaumen-agent` on an issue in the watched repository, read by polling notifications every 60 s or more (`dsh:src/sources/github.ts:128-145`), only from people on the list (`dsh:src/policy.ts:193-197`) | The board already does it: it opens the issue with the mention in the body (`lib/agent_board/board.ex:253`, `lib/agent_board_web/live/board_live.ex:2062`). The orchestrator API **does not create a ticket** (only Eval creates, `dsh:docs/001-domain.md:35`) and **does not answer questions** (the answer is a comment on the issue); it stops, retries and pauses (`POST tickets/:id/stop`, `tickets/:id/retry`, `executor/pause`, `dsh:src/app/api.ts:35-37`) | By role and global (`executor.model`, `dsh:src/policy.ts:91-97`), fixed when the session is born (`dsh:docs/003-execution.md:143`); today `deepseek-account/deepseek-flash/high`. There is no per-ticket choice | Routes read in the code; `GET state`, `settings`, `tickets` and `models` read live |
| **Claude Code** | Desktop app and CLI opened by the owner | `claude -p` (CLI 2.1.311): `--output-format json\|stream-json`, `--session-id <uuid>`, `--model`, `--fallback-model`, `--permission-mode`, `--allowedTools`, `--max-budget-usd`, `--add-dir`, `--append-system-prompt`, `--mcp-config`; `--max-turns` works but does not appear in `--help`. The final JSON has `session_id`, `num_turns`, `usage`, `modelUsage` and `total_cost_usd`. Call by absolute path: the asdf shim fails in this worktree. The Agent SDK (TypeScript/Python) is not installed and is not needed: the board talks to a process, not a library | Per execution (`--model`) | Flags read in `--help`; the output format was read from the binary, **not from an execution** |
| **Codex** | Desktop app and VS Code extension | `codex exec --json -o last.txt -m <modelo> -s workspace-write -C <dir> [--ephemeral] "<prompt>"` and `codex exec resume <id>` (CLI 0.162.1). No flag fixes the session id: one captures `thread.started` from `--json` or matches the `threads` table row by `cwd`, `created_at` and `source = 'exec'` (`originator = 'codex_exec'`). `exec` writes `approval_policy: never` | Per execution (`-m`); today `gpt-6-sol` with effort `xhigh`, with traffic going through a local URL on port 11434 (Ollama routing) | Flags read; the event format of `--json`: **not verified** |

Two side doors exist and are left out of the design: DSH has a dormant model route (`llm-pi-ai`) that would talk to Anthropic and OpenAI by API key (notes `alfred-dsh-api.md`), but that would be API billing, global per role, and not the Claude Code or Codex the owner uses; and DSH's `Executor` interface (`dsh:src/core/ports.ts:55-69`) would allow another executor, but the runtime instantiates `DshExecutor` directly (`dsh:src/app/runtime.ts:68`) and the worker depends on six tools injected into the session (`dsh:src/app/tools/executor.ts:23-104`). **Conclusion: the routing decision lives in the board, before the executor.**

### 3.3 Where usage lives and what it costs

| Executor | File | Fields | Counting rule | Link to the task | What "cost" is |
|---|---|---|---|---|---|
| **DeepSeek** | `~/.dsh/sessions/<diretório do ticket>/<sessão>/session.v4.jsonl.zstd`, already read by `AgentBoard.Usage.Harness` (#305) | `data.usage`: `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheWriteTokens` | Once per `data.message.id`, worker and subagents (contract, "Executor usage") | Exact: ticket directory → ticket → issue | The `deepseek-account` account is an account login with balance (wallet; a missing balance becomes `ACCOUNT_QUOTA`), not an API key. The board estimates by its table's price (US$ 0.28 / 0.42 per million, `lib/agent_board/ai/providers.ex`); without a cache price the value is a minimum, `≥` |
| **Claude Code** | `~/.claude/projects/<cwd codificado>/<sessão>.jsonl` and `<sessão>/subagents/agent-<id>.jsonl` (`isSidechain: true`) | `message.usage`: `input_tokens`, `output_tokens` (includes thinking), `cache_creation_input_tokens` (5 min and 1 h), `cache_read_input_tokens`, `server_tool_use`; `cost-state` rows with `totalCostUSD` per process | Only `type == "assistant"`, excluding `model == "<synthetic>"`, **one row per `message.id` in the whole set** (each block of a message repeats the final usage, and a forked session copies the parent's rows). In one agent-board session, 1,067 rows became 372 messages. The deduplicated sum matched Claude Code's own `cost-state`; side calls (Haiku) appear only in `cost-state` | `cwd`, `gitBranch` and `timestamp` on every row; `pr-link` rows with `prNumber` and `prRepository`; in a board execution, the `--session-id` chosen beforehand | Claude Max subscription (`organizationType: claude_max`, `billingType: stripe_subscription`). The US$ in `cost-state` and `total_cost_usd` is an estimate at list price, not an invoice. The real cost is the 5-hour and weekly quota, which **is not in the files** |
| **Codex** | `~/.codex/sessions/AAAA/MM/DD/rollout-*.jsonl` (older ones in `.jsonl.zst`) and `~/.codex/state_5.sqlite`, table `threads` | `token_count.info.total_token_usage`: `input_tokens` (includes cache), `cached_input_tokens`, `output_tokens` (includes reasoning), `reasoning_output_tokens`, `total_tokens`; `rate_limits`: `used_percent`, `window_minutes`, `resets_at`, `plan_type`, `credits`; `threads.tokens_used` | The total is cumulative per thread: the last one counts; per day, the difference between events. New files (since 2026-09-14) have `token_usage_record` per `response_id`. `last_token_usage` repeats and is not added | `threads.cwd`, `git_branch`, `git_sha`, `git_origin_url`, `source`, `originator`. The `title`, `preview` and `first_user_message` columns store conversation text and **are never** read | ChatGPT plan (`auth_mode: chatgpt`, no API key). There is no US$ anywhere; the currency is the `used_percent` of the weekly window (90% and credits at zero in the most recent reading) |
| **Board's own calls** | `ai_calls` table | tokens, `cost_micros` | one row per call (contract, "AI calls") | `task_id` | Provider API key; US$ estimated by the table |

**Three currencies, not one.** Adding Claude's list-price US$ to DeepSeek's spent balance would give a meaningless number. The visualization and the router show each executor in the currency it actually costs: DeepSeek in estimated US$ (with `≥` when a price is missing), Claude Code in used quota (unknown until someone proves how to read it, shown as `?`, never zero) with list-price US$ as a reference, and Codex in percentage of the weekly window. Measured tokens are the only common unit, and even they measure different things (Codex counts cache inside input; DSH and Claude count it outside).

### 3.4 (a) The visualization: where each task went

The unit is the **execution**: a session of an executor, assigned to a task or to "direct work in repository X". Assignment rules, strongest to weakest:

1. **Exact**: the board dispatched and stored the id (DSH ticket, Claude `--session-id`, Codex `thread.started`).
2. **By PR**: the session has a `pr-link` row (Claude) or a branch (`gitBranch`, `threads.git_branch`) that is the branch of a PR with `Closes #n` for a task. Requires storing the PR branch: `pull_requests` does not have that column (`lib/agent_board/board/pull_request.ex:21-32`).
3. **By repository**: `cwd` or `git_origin_url` from a board repository, without a PR: "direct work in o_colmex", without a task.
4. **Outside the board**: a repository the board does not know appears aggregated as "others", with the directory name.

The task is never guessed from conversation content: the reader selects numeric and metadata fields explicitly and records only counts.

Three screens:

- **Task inspector, "Executions"** (extends the "Executor do agente" section): one row per execution, with executor, model, start and end, tokens, cost in the executor's currency and the result (PR merged, block, failure). A task that moved from DeepSeek to Claude shows both.
- **"Executors" panel**: per day (7 and 30 days) and per executor, tasks, direct sessions without a task by repository, tokens, cost in each currency, the merged-task rate and time to merge. It answers "which tasks stayed in each context and how much each spent".
- **"Hoje" ("Today")**: what needs the owner, what is running and where, and the day's spend, across all repositories.

Reading hundreds of transcripts on every render does not fit: the contract today says `Usage.Harness` stores nothing and reads only with the inspector open. The design is a **usage ledger** like ElevenLabs' (`AgentBoard.ElevenLabs.Usage`): an Oban job in its own queue reads the files that changed (path, size and mtime as key) and writes one row per execution and per day, with the source. It is observed data stored with its source, and it changes a contract rule, which the PR updates along with it.

### 3.5 (b) Automatic routing

**Where it decides.** In the board, when the task is born (composer, voice, API). DSH does not choose executor or model per ticket (3.2). For DeepSeek, dispatching remains opening the issue with the mention; for Claude Code and Codex, it is starting a local runner (3.6). Every task remains an issue on GitHub, to keep the trail; an issue for another executor is born without the mention (DSH records an issue without a mention and does not act, `dsh:src/policy.ts:55-58`, not tested live) and with a label `executor:<nome>`.

**Signals**, in the order they enter the decision:

| Signal | Where it comes from | Weight |
|---|---|---|
| Hard constraint: DSH only serves `arena-rogue` | `GET state` (`accounts.repository`) | Eliminates DeepSeek in other repositories |
| Explicit owner choice ("manda pro Claude" — "send it to Claude") and approved facts ("no o_colmex, UI vai para o Claude" — "in o_colmex, UI goes to Claude") | The request; the facts table (F4.2) | Decides when it exists |
| Availability | Orchestrator up, paused and `load.running` against `maxWorkers` (`Orchestrator.load/0`, already read); binary and login present; Codex's last `rate_limits` (`used_percent`, `rate_limit_reached_type`); `ACCOUNT_QUOTA` in DSH; an available runner per executor | Eliminates whoever cannot serve now |
| Budget | Day's spend per executor in the usage ledger against each one's ceiling | Eliminates whoever exceeded the ceiling |
| Task type and size | The composer split is already a recorded call (`:propose_tasks`); it gains the fields `tipo` (UI, backend, docs, bug, research, infra) and `tamanho` (P, M, G), with no new call | Chooses the history row |
| History by repository, type and executor | Usage ledger + execution results: merged-without-correction rate, time to merge, blocks and questions, rework (child task by `origin_task_id` in 7 days), cost per merged task | Orders those that remain |
| Expected cost | Median cost of similar tasks, in the executor's currency | Breaks ties and appears in the confirmation |

The first version is a pure function, `AgentBoard.Routing.suggest/2`: rules in the order above, no model. It returns the executor, the reasons as a sentence, the alternatives and the expected cost. Each suggestion becomes a row in `routing_decisions` (task, suggested, chosen, mode, reasons, the snapshot of signals and who decided); that table is the basis for measurement.

**Modes** (Alfred's trust ladder, applied to a single type of decision):

1. **Suggest** (the initial one). The composer shows "Sugestão: Claude Code, porque o DSH não atende o o_colmex e o Codex está com 90 % da cota semanal" ("Suggestion: Claude Code, because DSH does not serve o_colmex and Codex is at 90% of the weekly quota"). The owner confirms or changes it; dispatch is the confirmed action, with the values ("Mandar #412 para o Claude Code no o_colmex, teto US$ 3?" — "Send #412 to Claude Code in o_colmex, ceiling US$ 3?").
2. **Confirm**. The board chooses; the owner approves each dispatch with one tap, or a batch.
3. **Automatic per category**. Offered, never turned on by itself, when a repository-and-type combination gathers 10 accepted suggestions in a row whose result was good; the first change made by the owner or the first bad result returns the category to the previous mode. It stays visible on a screen, with the history of each promotion and demotion.

**How to measure whether the choice was good.** For each execution: merged without human correction; time to merge; how many questions and blocks; how many retries; rework within 7 days; cost in the executor's currency. For the router: the acceptance rate of suggestions and, for changes, the result of the executor the owner chose against the median of what the router suggested in that category. Running the same task on two executors for comparison would cost double and is out of scope; the owner's change is the label that teaches.

**Fallback when an executor fails**:

| Failure | What happens |
|---|---|
| Transient before spending (network, 5xx, process that did not start) | Same executor; in DSH the automatic retry that already exists; in runners, a new attempt only if no token was spent |
| Unavailable (subscription quota, `ACCOUNT_QUOTA`, binary without login, orchestrator down) | The board proposes the next on the list with the reason and cost; in suggest and confirm modes, the owner approves; in automatic, only if the category allows it and before any spending |
| Content (tests fail, block, question) | Never switches on its own: it goes to Precisa de você ("Needs you"). "Reenviar para o Codex" ("Resend to Codex") is a confirmed action that continues the same branch |
| Ceiling reached midway | The runner stops (`--max-budget-usd` in Claude; in Codex, only by time, because there is no US$ ceiling) and the task enters Precisa de você with the spend |

A task never has two executions at the same time.

### 3.6 The new boundary: the board dispatching

> **Status (2026-11-08):** this boundary became the
> [ADR 0004](../decisions/0004-o-board-despacha-para-executores-locais.md)
> (D1, D2, D3 and D5 decided) and F3.1–F3.3 and F3.5 are implemented — see
> [contract — Dispatch](../maintainer-contract.md#dispatch-local-dispatch).
> F3.4 remains separate work.

Today the board reads the agent and writes to the runner through two API paths (contract, "Boundaries"). Starting Claude Code or Codex is a new write, which spends, and asks for an ADR before the code, with these proposed rules:

- **The process is not a child of the board.** The service restarts on every update (`launchctl kickstart`), and a process opened by `Port` risks dying with it (inference, not tested). The board asks the runner, a script with the session in a tmux or a launchd job, as `dsh-superagent` already runs, and then only observes: the result file, the transcript, the worktree and the PR.
- **Dispatching is an action in the action registry** (F2.3), confirmed with executor, repository, ceiling and expected cost, except in that category's automatic mode.
- **Budget is checked before starting**, as `Budget.check/1` before the network; the ceiling goes on the command line when the CLI accepts it.
- **One execution, one row**, with the session id and the decision that originated it. No paid execution retry without a decision.
- **Pause dispatch** is a global switch: what is running continues, nothing new leaves.
- **The same delivery contract for all three**: the runner prompt comes from `docs/agent/prompts/` (the workpad `## Relatório do agente`, the local gate on head and the merge policy), so Precisa de você, local CI and "Mesclados" ("Merged") work the same for any executor.

## 4. Phased plan

Effort: **P** ≤ half a day · **M** 1–2 days · **G** > 2 days. Each item is an issue or a PR. The order goes from cheapest and most valuable to most ambitious: first the board **sees** the three tools, then **suggests**, then **dispatches**, and finally **decides on its own** where it has already proven to choose well.

### Phase 0 — Owner decisions (no code)

| # | Decision | Why it blocks | Needs |
|---|---|---|---|
| D1 | Can the board start local Claude Code and Codex through a confirmed action (the boundary in section 3.6)? | Without it phase 3 does not exist; phases 1 and 2 do not depend on it | The owner |
| D2 | Ceilings: monthly budget (Alfred's profile said US$ 300 per month; does it apply to the platform?), per-task ceiling on each executor and the subscription quota reserve for direct use | The router and runners check before starting | The owner |
| D3 | Use the Claude Max subscription with `claude -p` and the ChatGPT plan with `codex exec`, for personal use, dispatched by the board | Subscription terms of use; no new credential | The owner confirms the terms |
| D4 | Which repositories enter the board (today 2; the owner worked in 11 during the week) | Assignment and "Today" depend on it; sync spends GitHub API quota per repository | **Decided on 2026-11-07: only the current ones**, `sallaumen/arena-rogue` and `sallaumen/o_colmex`. Claude and Codex usage in other repositories appears as outside the board, without a task |
| D5 | Who opens and merges Claude and Codex PRs: the `sallaumen-agent` bot (like DSH) or the owner's account; and whether the same DSH merge policy applies | Runners need an authenticated `gh` with write access | The owner; if it is the bot, its token in the runner environment |

### Phase 1 — See the three tools (read-only)

| # | Item and where | Effort | Value | Depends on | Risk | Done when |
|---|---|---|---|---|---|---|
| F1.1 | **Claude Code usage reader**: `AgentBoard.Usage.ClaudeCode` reads `~/.claude/projects/**/*.jsonl` (sessions and subagents), deduplicates by `message.id` across the whole set, groups by session, day, `cwd` and `gitBranch`; tests with synthetic transcripts | M | High: the owner's largest volume of work starts having a number | — | Claude Code's internal format changes in a new version; file volume (thousands) | The sum of a real session matches its `cost-state`; no text field is read (a test fails if the reader touches `message.content`) |
| F1.2 | **Codex usage reader**: `AgentBoard.Usage.Codex` reads `threads` (explicit columns, via Exqlite like `AgentState`) and the rollouts (`zstd` for old ones), by difference of the cumulative total; stores the last `rate_limits` | M | High: Codex enters the picture, with the weekly quota visible | — | Ollama routing may change fields (not verified); the 247-thousand-token gap in a recent file | `tokens_used` of two threads matches the last total; `title`, `preview` and `first_user_message` out of every query |
| F1.3 | **Usage ledger**: table per execution and per day, an Oban job in a `usage` queue that reads only changed files (path, size, mtime); DSH joins by reusing the `Usage.Harness` parser; a new section in the contract | M | High: the basis for everything that follows | F1.1, F1.2 (can be born with one of them) | Changing the rule "Usage.Harness stores nothing" without leaving two sources of truth | Rereading the same files changes no row; a new file appears within one cycle; the contract describes the ledger |
| F1.4 | **PR branch and assignment**: `head_ref` column in `pull_requests` (sync already fetches the PR) and the four assignment rules from section 3.4 | P | Medium: links direct sessions to tasks | — | A PR without `Closes #n` has no task (that is the right behavior) | A Claude session that opened a task's PR appears in that task, by `pr-link` or branch |
| F1.5 | **"Executors" panel and "Executions" in the inspector** (section 3.4), each executor in its own currency, `?` for the unknown | M | High: answers "where did it go and how much did it cost" by task, day and executor | F1.3, F1.4 | Treating an estimate as an invoice: each value says whether it is measured, estimated or unknown | The owner sees the last 7 days of the three executors without opening any tool |
| F1.6 | **Day summary with a wall clock**: on every tick, "has today's run already happened after 8 a.m.?"; done, spent per executor, failures, what the board did on its own (retries); on the board and in voice; template without a model | P/M | Medium: Alfred's daily report, without a new channel | F1.3 only for the spending line (the rest comes earlier) | Firing twice after a restart: the day's execution is a single row | With the Mac asleep at 8 a.m., the summary comes out when it wakes, once |
| F1.7 | ~~**Owner repositories in the board**~~: does not apply under decision D4 (only the current repositories); reopen if the owner changes their mind, adding via the existing API (`POST /api/repos`) and measuring sync cost | — | — | D4 | — | — |

### Phase 2 — The board suggests, the owner chooses

| # | Item and where | Effort | Value | Depends on | Risk | Done when |
|---|---|---|---|---|---|---|
| F2.1 | **"Today" view** across all repositories, from `Overview.repo_overview/0` and the usage ledger | M | High: the home screen stops being a repository | F1.3 | One extra read per render: it joins the same board read (contract, "Real-time") | What needs the owner across repositories appears in a single list, with the repository on each item |
| F2.2 | **Executor on the task**: `executor` field (`dsh`, `claude`, `codex`), choice in the composer and in voice, label `executor:<nome>` on the issue; an issue for another executor is born without the mention | M | High: the owner already creates everything on the board, even before dispatch exists | — | DSH acting on an issue without a mention (not expected, not tested live) | A `claude` task becomes an issue without a mention and with a label; DSH does not pick it up |
| F2.3 | **Action registry with risk**: `AgentBoard.Actions` with every board write, its risk, the sentence with the actual values and the record of the decision; UI, voice and API go through it; reject red without confirmation in code | M | High: Alfred's gate, and the prerequisite for dispatching anything that spends | — | Regression in confirmations that already work (voice, `AgentAction`) | One test per action; the same confirmation sentence on screen and in voice; no write outside the registry |
| F2.4 | **Router in suggest mode**: `AgentBoard.Routing.suggest/2` (pure) and the `routing_decisions` table; the composer shows the suggestion, the reasons and the expected cost | M | High: starts measuring whether the board would choose well, with no risk | F1.3, F2.2 | Suggestion too obvious at first (no history, only rules) | Every created task has a row with suggested, chosen and reasons |
| F2.5 | **Type and size in the split**: new fields in the `:propose_tasks` schema in the registry, with no new call | P | Medium: a signal for the router and for reports | — | The model classifying poorly: the owner corrects it in review, and the correction becomes data | The field appears on the composer receipt and on the task |

### Phase 3 — The board dispatches

| # | Item and where | Effort | Value | Depends on | Risk | Done when |
|---|---|---|---|---|---|---|
| F3.0 | **ADR 0004, "The board dispatches to local executors"**, and the new contract section (rules in 3.6) | P | High: unblocks the phase | D1, D2, D3, D5 | — | ADR accepted by the owner |
| F3.1 | **Claude Code runner**: script in `scripts/runners/` that creates the worktree, runs `claude -p --session-id … --output-format json --max-budget-usd …` in a tmux, writes the result; `AgentBoard.Runners` starts it through the confirmed action and observes files, transcript and PR | G | Very high: the first work in Claude without opening Claude | F3.0, F2.2, F2.3 | Permissions: in headless mode Claude needs a mode without questions, the same risk level as DSH (`danger-full-access`); a board restart must not kill the execution | A task in o_colmex becomes a PR merged by the runner, with the execution and cost in the inspector, and the board restarted midway does not interrupt it |
| F3.2 | **Codex runner**: the same fit with `codex exec --json`, capturing the thread id | M | High | F3.1 | No US$ ceiling in Codex: limit by time and by weekly quota | Same as F3.1 with Codex |
| F3.3 | **Pause dispatch and one execution per task**: global switch and per-task lock; ceilings checked before starting | P | High: Alfred's stop button | F3.1 | — | With pause on, nothing new leaves; a second execution of the same task is refused |
| F3.4 | **Objective**: a group of tasks with a done criterion, progress computed from the tasks, able to cross executors; the composer creates the objective when the split returns more than one task | M | Medium/high: Alfred's "background objective" | F2.2 | Becoming a second project manager: the objective has no state of its own beyond the criterion | The board says "objetivo X: 3 de 5 tarefas mescladas" ("objective X: 3 of 5 tasks merged") without anything written by hand |
| F3.5 | **Fallback and retry in runners** (table in 3.5) | M | High: an exhausted quota no longer stops the work | F3.1, F3.2 | Spending twice: no retry after spending without a decision | A Codex without quota makes the board propose Claude with the reason and cost |

### Phase 4 — The board decides where it has already proven to choose well

| # | Item and where | Effort | Value | Depends on | Risk | Done when |
|---|---|---|---|---|---|---|
| F4.1 | **Confirm and automatic per category modes**, with the offer after 10 correct choices in a row and the return on the first error (3.5) | M | Very high: it is the owner's goal | F2.4, F3.1–F3.5 and weeks of history | Rising without proof: the board only offers; the owner turns it on | A category on automatic dispatches without asking and returns to suggest mode on the first change |
| F4.2 | **Approved routing facts**: a small table, proposed by the board from history, approved, corrected or deleted by the owner | M | Medium: preferences become a visible rule | F2.4 | Stale facts: each shows the date and origin | "No o_colmex, UI vai para o Claude" appears as a reason for the suggestion |
| F4.3 | **10-minute weekly review**: by executor and type, the owner's changes, failures and suggested rule changes, which the owner approves or rejects; the delivery check (gate on head, `Closes #n`) also for Claude and Codex PRs | M | Medium | F1.5, F2.4 | — | An approved suggestion changes a router rule and is recorded |
| F4.4 | **Board as a read-only MCP server** for direct sessions ("what is in the queue?", "how much did I spend today?") | M | Low/medium | F1.5 | Exposing board data beyond localhost | A Claude Code session reads the board queue without writing anything |

### Parallelism and what needs the owner

- **Can start now, in parallel:** F1.1, F1.2, F1.4, F1.6 (without the spending line), F2.3 and F2.5. None needs a decision or a credential.
- **In sequence:** F1.3 after F1.1 and F1.2; F1.5 after F1.3 and F1.4; F2.4 after F1.3 and F2.2; the whole phase 3 after F3.0; F4.1 after weeks of `routing_decisions`.
- **Needs the owner:** D1 to D5. New credential only in D5, if the runners use the bot: the `sallaumen-agent` token in the runner environment. The Claude Max and ChatGPT logins already exist on this machine.
- **Shared files**: F1.3, F1.4, F2.2 and F2.5 bring migrations; two sessions must not write migrations at the same time without agreeing on the timestamp. F2.3 touches `BoardLive`, `Conversation` and the controller, and must not run alongside another item that touches those files.

## 5. What not to do

- **Telegram and other channels (WhatsApp, Slack, Discord), for now.** Owner decision on 2026-11-07. What is postponed: alerts outside the browser, answering a question or approving from the phone, and creating a task by message. When it comes back, the channel enters as another door of the action registry (F2.3), with a sender list and the same confirmation, and Pokex's implementation is the reference. Before that, the board API must not be exposed beyond `127.0.0.1`: today it writes without authentication.
- **Do not build Alfred's engine** (Python, FastAPI, a third-party agent engine, the profile's Hermes, a VPS). The board is already the control center; replacing the base would cost everything that exists and would not bring routing, which is what is missing.
- **Do not let the assistant write automations, mini-apps or connectors for itself.** It clashes with "every model call is in the registry" and with the board contract.
- **Do not control the computer through the screen** or give the board a shell. The ones who touch code are the executors, in their worktrees.
- **Do not change DSH's model on every ticket** with `PUT settings/executor`: it is global and would race between tickets. Nor enable DSH's `llm-pi-ai` route with API keys to "have Claude in DSH": it would be API billing and not the Claude Code the owner uses.
- **Do not run Claude Code or Codex as a child process of the board** (section 3.6).
- **Do not read conversation content to assign sessions**: only metadata and numbers, with fields chosen one by one.
- **Do not sum across currencies** or show zero for the unknown: quota without a reading is `?`, a missing price leaves the cost as a minimum (`≥`).
- **Do not let the model confirm anything or raise autonomy.** Confirmation comes from the owner; the board only offers the rise.
- **Do not run the same task on two executors to compare.** The owner's change is the label.
- **Do not use a local model to classify tasks** (Alfred's profile cited Ollama with Llama). The rules and the split call that already exists are enough; reassess only if the rules err too much.
- **Do not use the Claude Agent SDK with the subscription login** in a product: the personal path is `claude -p` with the owner's own login (D3).

## 6. Open questions

> **Update 2026-11-08:** D1, D2, D3 and D5 were answered in
> [ADR 0004](../decisions/0004-o-board-despacha-para-executores-locais.md).
> Questions 6–8 remain open.

1. Can the board start Claude Code and Codex on this machine (D1)? If not, phases 1, 2 and 4.2–4.4 still apply, and dispatch remains manual.
2. What is the platform's monthly budget and each executor's per-task ceiling (D2)? How much of the subscription quota is reserved for the owner's direct use?
3. Do the subscription terms cover headless executions triggered by the board, for personal use (D3)?
4. ~~Which repositories enter the board (D4)?~~ Answered on 2026-11-07: only the current ones.
5. Who opens and merges Claude and Codex PRs, and under what policy (D5)?
6. Should DSH gain more repositories (one orchestrator per repository), or do the other repositories stay with Claude and Codex?
7. What counts as a "good choice" for the owner: merging without correction within how many hours, at what maximum cost?
8. How to read the Claude subscription quota without opening the app? Without that, Claude enters the router with unknown availability.

## 7. Not verified

- The real output of `claude -p --output-format json` and `codex exec --json`: the format was read from the binary and `--help`, without a paid execution.
- What `--max-budget-usd` limits on a subscription account (`--help` says "API calls"; the list-price estimate is the candidate).
- Where to read Claude Max's 5-hour and weekly quota without the interface; and when Claude Code writes the `cost-state` rows.
- The effect of routing through port 11434 (Ollama) on Codex usage and quota fields; the 247,213-token gap between the `token_usage_record`s and the total in a recent file; the values of `--thread-source`.
- Whether the `deepseek-account` is prepaid or a subscription, and the real prices of `deepseek-flash` and the cache.
- Whether a process opened by `Port` dies when launchd restarts the board (section 3.6 assumes it does, out of caution).
- Whether DSH ignores, live, an issue without a mention in the repository it watches (the code says it only records it, `dsh:src/policy.ts:55-58`).
- Who triggered the 8 `sdk-cli` sessions found in the Claude Code transcripts.
- The subscription terms of use for headless executions (question 3).

## 8. How to reproduce the spikes

Read-only; none of the commands below prints conversation text or a secret.

```sh
# versões e flags
claude --version; claude --help | grep -E 'max-budget|output-format|session-id|fallback-model|permission-mode'
codex --version;  codex exec --help | grep -E -- '--json|--cd|--ephemeral|--sandbox'

# Claude Code: one session, deduped by message.id (numbers only)
F=$(ls -t ~/.claude/projects/-Users-tavano-projects-agent-board*/*.jsonl | head -1)
jq -c 'select(.type=="assistant" and .message.model!="<synthetic>")
       | [.message.id, .message.usage.input_tokens, .message.usage.output_tokens,
          .message.usage.cache_creation_input_tokens, .message.usage.cache_read_input_tokens]' "$F" \
  | awk -F, '!seen[$1]++ {u++; i+=$2; o+=$3; w+=$4; r+=$5} END {print u, i, o, w, r}'
grep -l '"type":"cost-state"' ~/.claude/projects/*/*.jsonl | wc -l

# Codex: threads por origem (nunca title, preview ou first_user_message)
sqlite3 -readonly ~/.codex/state_5.sqlite \
  "select source, originator, count(*), sum(tokens_used) from threads group by 1, 2;"
jq -r '.auth_mode' ~/.codex/auth.json     # só o modo, nunca os tokens

# DSH: estado e modelos (GET apenas)
curl -s -H 'x-orchestrator-request: 1' http://127.0.0.1:3082/orchestrator/api/state | jq 'keys, .load, .paused'
curl -s -H 'x-orchestrator-request: 1' http://127.0.0.1:3082/orchestrator/api/models | jq '.routableProviders'

# Oban.Cron does not recover a missed slot
grep -n 'Expression.now?' deps/oban/lib/oban/cron.ex
```
