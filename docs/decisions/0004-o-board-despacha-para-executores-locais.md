# ADR 0004 — The board dispatches to local executors

- **Decision:** the board can dispatch a task to the local Claude Code or
  Codex through a **confirmed action** from the action registry, with budget
  and quota checked before starting, a process that is not a child of the
  board, and one row per execution. The board keeps observing; it does not
  talk to the model or control the machine.
- **Status:** **accepted on 2026-11-08 by the owner**. D1, D2, D3 and D5 were
  answered (below) and Phase 3 is implemented in `AgentBoard.Runners`; the ADR
  records the boundary and the contract under "Dispatch (despacho local)".
- **Scope:** the rules of section 3.6 of
  [`docs/research/alfred.md`](../research/alfred.md); it does not change the
  contract in this delivery.

## Problem and context

The board already sees the three tools and already knows where a task should go:

| Piece | State on 2026-11-07 |
|---|---|
| Executor on the task, issue without mention and label `executor:<nome>` (F2.2) | implemented |
| Action registry with risk, confirmation phrase and recorded decision (F2.3) | implemented |
| Usage ledger per execution and day, with attribution per PR and branch (F1.3, F1.4) | implemented |
| Router suggesting by rules and recording the decision (F2.4) | implemented |
| Type, size and expected cost in the composer (F2.5, F2.4) | implemented |
| Resumo do dia (Daily summary) and the Hoje (Today) view (F1.6, F2.1) | implemented |
| Someone starting Claude Code or Codex programmatically | **does not exist** |

DSH is the only executor the board triggers on its own, and it does so through
a path that already exists: it opens the issue with the mention and the
orchestrator finds it (`docs/research/alfred.md`, 3.2). For Claude Code and
Codex there is nothing mentionable: the trigger is `claude -p` and
`codex exec`, local processes that spend the owner's subscription. Doing this
is a new write that spends, so it needs an ADR before the code (the contract,
"Board actions", already requires every write to go through the registry).

What constrains the design:

- The service restarts on every update (`launchctl kickstart`); a process
  opened by `Port` can die with the board.
- Both subscriptions are personal: Claude Max and the ChatGPT plan. There is
  no new API key, and the real cost is a quota that the files do not store.
- The board shows only observed data; the state of an execution has to be read
  from what the runner leaves (result file, transcript, worktree, PR).
- A task cannot have two executions at the same time, and no paid retry can
  happen without a decision.

## The proposed rules

These are the rules from section 3.6 of the plan, in contract form.

1. **The process is not a child of the board.** The board asks the runner — a
   script in `scripts/runners/` with the session in a `tmux` or a `launchd`
   job, as `dsh-superagent` already runs — and then only observes: the result
   file, the transcript, the worktree and the PR. Restarting the board does
   not interrupt the execution.
2. **Dispatching is an action from the registry.** It is red, with the phrase
   that names executor, repository, task, ceiling and expected cost
   (`AgentBoard.Actions`). Confirmation exists on screen, by voice and in the
   API; automatic mode per category (F4.1) is the only exception, and only
   after the owner turns it on.
3. **The budget is checked before starting.** A `Budget.check/1` for the
   executor, separate from the budget of the board's calls, compares the day's
   and month's spending with the ceiling. The ceiling goes on the command line
   when the CLI accepts it (`--max-budget-usd` in Claude Code); Codex, which
   has no ceiling in US$, has a time ceiling and the weekly quota as its limit.
4. **One execution, one row.** Each execution is born from a row in
   `routing_decisions` and writes the session id, the start, the end and the
   result to the usage ledger. No paid retry without a new decision; a task
   never has two executions at the same time.
5. **Pausing dispatch is a global switch.** With the pause on, what runs
   continues and nothing new leaves. The per-task lock and the pause are
   checked before the runner, not inside it.
6. **The same delivery contract for all three.** The runner's prompt comes from
   `docs/agent/prompts/` (the workpad `## Relatório do agente` (Agent report),
   the local gate on head and the merge policy), so "Precisa de você",
   "CI local" (local CI) and "Mesclados" (Merged) work the same for any
   executor.
7. **Failure does not become a silent switch.** Transient before spending: the
   same executor. Unavailable or ceiling: the board proposes the next one with
   reason and cost; in automatic mode, only before any spending. Content
   failure (test, block, question) never switches on its own: it goes to
   Precisa de você, and "Reenviar para o Codex" (Resend to Codex) is a
   confirmed action that continues the same branch.
8. **The credential belongs to the owner and does not enter code, log or
   prompt.** If D5 chooses the bot, its token stays in the runner's
   environment; the board neither stores nor prints secrets.
9. **None of this leaves localhost.** The board API gains no authentication in
   this ADR; dispatch is triggered by the owner on their machine.

## Owner decisions (2026-11-08)

| # | Decision | Answer |
|---|---|---|
| **D1** | Can the board start local Claude Code and Codex through a confirmed action? | **Yes.** The red `dispatch_task` action, with the phrase and the ceiling, is the only door. |
| **D2** | Monthly budget, per-task ceiling and subscription reserve | **US$ 300/month, US$ 5 per task in Claude Code, 30 minutes in Codex and 50% of the weekly quota reserved**, all configurable in the Configurações → Despacho local (Settings → Local dispatch) form (`dispatch_*`); no value is summed across executors. |
| **D3** | Do the subscription terms cover headless execution for personal use? | **Yes, for personal use**, confirmed by the owner; no new credential is created. |
| **D5** | Who opens and merges the PRs? | **The owner's account**, with `gh` already authenticated and the same delivery policy as DSH; the bot token does not enter the runner. |

D4 (which repositories enter the board) was already answered: only
`sallaumen/arena-rogue` and `sallaumen/o_colmex`; use in other repositories
appears as "fora do board" (outside the board), without a task.

Smaller questions left for operations: reading Claude's quota without opening
the app (currently unknown), the maximum time of an execution before the
silence warning, and the prompt variant per executor.

## Alternatives

| Alternative | Benefit | Cost or risk |
|---|---|---|
| Keep dispatch manual (the owner opens Claude Code and Codex) | No credential, no new process, no term risk | The board does not close the cycle; the owner keeps opening the tool, which is what phase 3 wants to avoid |
| The board starts the process as a child (`Port`/`System.cmd`) | Simpler local implementation, no tmux or launchd | A board restart can kill the execution; contradicts "the process is not a child of the board" and service updates |
| Use the Agent SDK (TypeScript/Python) with the subscription login | Richer API than the CLI | The SDK is not installed, and using the subscription in a product is exactly what section 5 of the plan forbids; the `claude -p` CLI is the personal path |
| Use DSH's `llm-pi-ai` route with API keys | One place for the models | It would be API billing, global per role, and not the Claude Code or Codex that the owner uses |
| One runner per executor, with confirmed action and budget (proposal) | Keeps the board as control center, preserves observation and the trail | Requires the four processes (Claude, Codex, pause, ceiling) and the answers D1–D3 and D5 |

## Choice and consequence

The proposal keeps the board in the role it already has: the control center
that **observes** and **asks**, never the process that executes. The runner is
a replaceable detail; the contract is the action registry, the budget before
spending, and one row per execution. The owner accepted D1–D3 and D5 on
2026-11-08; the implementation came in separate PRs, in the plan's order:

F3.1 (Claude Code runner, worktree, `--session-id`, result and observation),
F3.2 (Codex runner, `codex exec --json` and thread capture), F3.3 (global pause
and one execution per task) and F3.5 (failure classification, retry and
executor switch only with a new confirmation) are implemented and tested. F3.4
(objective with a definition of done) remains as separate work.

## Risks and limits

- **Subscription terms:** the biggest risk is not technical; D3 was confirmed
  by the owner for personal use, and dispatch remains local, with no product.
- **Shared quota:** a dispatched execution consumes the same quota the owner
  uses by hand; D2 decided to reserve 50% of Codex's weekly window, and
  Claude Code has a per-task and per-month ceiling.
- **Surviving process:** the runner needs a place that survives the board and
  logout; tmux or launchd, never a `Port`.
- **Owner's machine:** the runner runs with the permissions DSH already uses
  (`danger-full-access`); the board gains no shell or screen control.
- **Data:** the usage ledger still does not read conversation text; the runner
  delivers the result through the workpad and the PR, not through a new
  channel.
- **Cost of a mistake:** an execution lost mid-way can leave a worktree and a
  branch; cleanup already exists in `scripts/agent/cleanup.sh` and remains the
  owner's.

## Rollout and review

The first delivery was the ADR and the line in the index; the implementation
came in separate PRs (`AgentBoard.Runners`, the `scripts/runners/run.sh`
script, the `dispatch_task` action, the pause and the observation) and the
contract's "Dispatch (despacho local)" section. Review when:

- the owner wants to change the ceilings, the reserve or the default model;
- Claude Code or Codex change the `--json`/`cost-state` format (the
  usage-ledger reader already covers what exists today);
- the subscription quota can be read without opening the app — the router
  stops treating Claude's availability as unknown.

References: [`docs/research/alfred.md`](../research/alfred.md) sections 3.4,
3.5, 3.6 and 4; [`docs/maintainer-contract.md`](../maintainer-contract.md)
sections "Board actions", "Executors", "Routing", "Usage ledger" and
"Attribution"; [`ADR 0003`](0003-ciclo-de-vida-do-agente.md) for the lifecycle
and the automatic retry that already exists.
