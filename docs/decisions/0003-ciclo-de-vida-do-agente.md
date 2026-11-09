# ADR 0003 — Agent lifecycle in four edge cases

- **Decision:** record, with file and line citations, what `dsh-superagent` and the board do when the issue is closed during the run, when DSH restarts with a `running` Assignment, when a second mention arrives on the same issue, and when the ticket's PR is closed without merge; and propose the rules the [contract](../maintainer-contract.md) will have for each case. The contract does not change in this PR.
- **Status:** proposed. The behavior is documented; the rules await a PR in the contract and code in the board. Amendment of 2026-11-07: the owner authorized one write to the DSH API, the automatic retry of a transient failure (section "Automatic retry"), already in the contract.

## Problem and context

The research [`docs/research/symphony.md`](../research/symphony.md) (section 5, workstream 3) concluded that no one could answer what DSH does in these four situations, and that this is what will hurt most when parallelizing (`executor.maxWorkers > 1`). openai/symphony's `SPEC.md` (commit `be10a1b`) was used as a checklist, not as a model: §7 (states), §8 (tick, reconciliation, obsolete dispatch), §14 (failures and restart) and §18 (conformance checklist).

Sources read, all by static reading; nothing was executed:

| Side | Files | Prefix in citations |
|---|---|---|
| DSH (`/Users/tavano/Documents/deepseek-harness/default-workspace/dsh-superagent-prototype`) | `src/core/tickets.ts`, `intake.ts`, `assignments.ts`, `model.ts`, `stage.ts`; `src/executor/dsh.ts`; `src/sources/github.ts`, `github-trigger.ts`, `github-pull.ts`; `src/app/effects.ts`, `runtime.ts`; `docs/001-domain.md`, `002-authorization.md`, `003-execution.md`, `007-architecture.md`; `prompts/`; `tests/core-engine.spec.ts` | `dsh:` |
| Board (this repository) | `lib/agent_board/sync.ex`, `live.ex`, `agent_state.ex`, `board.ex`, `work.ex`, `sync/freshness.ex`, `board/task.ex`; `docs/maintainer-contract.md`; `test/agent_board/sync_repo_test.exs` | no prefix |
| Symphony | `SPEC.md` at `be10a1b` | `SPEC.md:` |

DSH vocabulary (`dsh: docs/001-domain.md:35-37`): a **Ticket** is open until it has `ended` (`model.ts:318`); an **Assignment** goes `pending → running → ended` on its own (`model.ts:211,218-233`); the ticket ends with an `outcome` in `completed | merged | closed | dropped | stopped` (`model.ts:271-273`); a **Subscription** delivers every message in the Thread to the ticket as **Input**, and a human message resurrects an ended ticket without a new Eval (`001:37`, `002:125-129`).

## The four situations

### 1. The issue is closed on GitHub while the ticket is `running`

**What DSH does: nothing.** Closing an issue does not become a Trigger, an Input or a ticket end.

- The GitHub source reads the issue in two places, and in both it only looks at author, creation date and comments since the cursor: `readNotified` (`dsh: src/sources/github.ts:344-374`, body only if created after the cursor at 355-356, comments at 357) and `pollThread` (`github.ts:440-459`, the issue is read only to fill `isPr` and the title at 446-451). The `state` field exists in the schema (`github-trigger.ts:34-38`) and is not consulted on any path; the only uses of `.state` are for PRs (`github-pull.ts:48,58`).
- The only ticket end coming from the source is `threadClosed`, called only by `closePull` (`github-pull.ts:80-84`), which runs for the open tickets' PRs (`github.ts:404-413`), never for issues. `docs/003-execution.md:92-106` lists how a ticket ends: `ready`/`dropped` report, PR close, stop. A closed issue is not on the list.
- The worker is not notified: `prompts/` and `skills/` do not mention a closed issue (the only occurrences of "closed" are `prompts/subscriptions.md:5` and `prompts/dispatch.md:10`, both about PR).
- So the worker continues, and the ticket ends with whatever the worker does next: `ready` without PR → `completed`; `ready` with PR → waits for the PR to close and ends `merged` or `closed` (`dsh: src/core/assignments.ts:129-132`, `tickets.ts:77-90`); `dropped` → `dropped`. An open PR for a closed issue stays open until a person acts.
- Worktree and PR stay. The executor's only `rmdir` is for an empty directory after a `prepare` that failed (`dsh: src/executor/dsh.ts:255-259`); no ticket end removes the directory. The SPEC requires the opposite: terminal state in the tracker → stop the worker and clean the workspace (`SPEC.md:831-839` §8.5 B, `841-849` §8.6, `1713-1715` §14.4, `2228-2229` §18.1), and the worker itself rechecks the issue state on every turn (`SPEC.md:662-674` §7.1).

**What the board shows today.**

- The board's **Parar** (Stop) button closes the issue and marks the task `stopped` (`lib/agent_board/board.ex:353-366`); the orchestrator client is read-only (`docs/maintainer-contract.md:16`, `:262`), so the board never calls DSH's stop (`dsh: src/core/tickets.ts:160-163`). Per the item above, the agent keeps working. The `stopped` task leaves every overlay (`sync.ex:439`, `live.ex:86`): the board says "parado" (stopped) while the worker runs and may open a PR.
- If the issue was closed directly on GitHub: the sync only replaces `title`, `url` and `updated_at` of an existing task (`sync.ex:259-262`); "closed → done" applies only on the first insert (`sync.ex:247-258`; the test `test/agent_board/sync_repo_test.exs:527-537` covers only that case). `apply_overlay` refuses an overlay that is not `done` on a closed issue (`sync.ex:433-434`), but the 10 s poller does not know the issue state and applies `running` anyway (`live.ex:74-101`). The task stays "rodando" (running) until the worker reports, then "para revisar" (needs review), and only becomes `done` through a merged or closed PR (`board.ex:60-86,96-121`). With `completed` (ready without PR) it stays "para revisar" forever.

**What the board should show.** A task whose ticket is alive on a closed issue, including after the board's Parar, appears in "Precisa de você" (Needs you) with the reason "o agente continua nesta issue fechada; o board não o parou" ("the agent continues on this closed issue; the board did not stop it") and the action that resolves it (stop through the DSH API, if the contract starts allowing a write; otherwise the `scripts/dsh-superagent` command or the DSH panel). "Parado" only when SQLite shows `ended.by == "human"`.

**Not verified.** The reading is unambiguous in the code, but there was no execution. Experiment: open a test issue with `@sallaumen-agent` and a request that takes a few minutes; when `scripts/agent/tickets.sh 1` shows `progress`, run `gh issue close N`; wait for two polls (`pollSeconds`, 60 s by default); in SQLite (`$STATE_DIR/orchestrator.sqlite`, `scripts/agent/_common.sh:3-5`) check that `json_extract(value,'$.ended')` is still null and `$.inputs` gained no entry; let the worker finish and check the open PR and the worktree at `work/<nome>`; in the board, check `tasks.state` at each phase and repeat with the board's Parar instead of `gh issue close`.

### 2. DSH restarts with a `running` Assignment

**What DSH does: resumes, with a recovery note; nothing is left orphaned and nothing becomes `failed`.**

- On startup, `Runtime` calls `executor.resume()` (`dsh: src/app/runtime.ts:214`). For each open ticket with a `running` Assignment, the executor cancels the session's turn while keeping the inbox, stops the jobs and reports `assignmentInterrupted` (`dsh: src/executor/dsh.ts:524-537`).
- `Assignments.interrupted` (`dsh: src/core/assignments.ts:83-92`): if the last report is not `waiting|ready|blocked|failed`, or an Input arrived after it (`busy`), the Assignment ends with `endedReason: 'hostRestarted'` and a new `pending` is born with the recovery note (`assignments.ts:21`: inspect worktree, git and GitHub before repeating an external action) ahead of the Inputs that were waiting (`tickets.ts:318-337`); if the report was settled and nothing arrived after it, the session is kept and only the pending Inputs are delivered. `docs/003-execution.md:144-152` describes this; `tests/core-engine.spec.ts:701-732` proves both branches.
- The launch is a durable effect in SQLite (`dsh: src/app/effects.ts:42-45`); the shutdown `drain` leaves the rows for the next startup (`effects.ts:98-102,136-137`). The launch reuses the same `worker-<ticket>` session and the same directory; the second Assignment's message says only what is new (`dsh.ts:449-464`). Contrast with the SPEC: Symphony persists nothing and re-dispatches from the tracker (`SPEC.md:1690-1704` §14.3; `2239` §18.2 lists persistence as a TODO). Here DSH is stronger than the checklist.
- While the process is **down** (no restart), SQLite does not change: `assignments[-1].state == "running"`, `idleAt` null if the turn was mid-flight.

**What the board shows today.**

- `AgentState.normalize` reads the last Assignment (`lib/agent_board/agent_state.ex:134-162`); `running_ticket?` is `assignment == "running"` with `idle_at` null (`sync.ex:524-525`); the `running` overlay is reapplied every 10 s (`live.ex:36,74-101`). Throughout the outage the task says "rodando".
- Freshness uses the WAL mtime as a heartbeat (`agent_state.ex:60-81`): with a `running` ticket and no write for more than `agent_running_ttl` (120 s, `sync/freshness.ex:14,76-80`), the header goes to "Dados atrasados" (Delayed data) and the source "Processo do agente" (Agent process) says "Sem sinal" (No signal) (`freshness.ex:182-194`). The task card does not change. The orchestrator API (`AgentBoard.Orchestrator.load/0`, `maintainer-contract.md:219`) would answer "down" at the same instant, but freshness does not consult it.
- After the restart: the new Assignment is born `pending`, `ticket_state` returns `nil`, and the card stays in the previous state ("rodando") until the launch marks it `running` (`assignments.ts:34-43`). The new `startedAt` advances `tasks.started_at` (`sync.ex:448-455`, `live.ex:95-100`), and the Fila (Queue) metric, which counts from entry to `started_at` (`maintainer-contract.md:217`), starts using the resume clock.

**What the board should show.** With a `running` ticket and an unreachable orchestrator (API down or WAL stopped beyond the TTL), the card says "agente fora do ar; o ticket retoma no reinício" ("agent is down; the ticket resumes on restart"), not "rodando"; freshness asks the API before claiming "Sem sinal" because of a long turn. `tasks.started_at` is the `startedAt` of the **first** Assignment, so that restart and retry do not reset the queue.

**Not verified.** (a) Whether DSH writes to SQLite during a long turn without a report: `Passes` runs every 2 s (`dsh: src/app/passes.ts:28`) but only writes when there is work; a three-minute turn without Input can raise a false "Sem sinal". (b) The exact sequence in the board. Experiment: with a ticket in `progress` and `idleAt` null, stop DSH (`scripts/dsh-superagent stop`); check `tasks.state` and the header at 30 s and at 150 s; start it again; check in SQLite that `assignments[#-2].endedReason == 'hostRestarted'`, `assignments[#-1].state` goes through `pending` and `running`, the input `text` contains "The host restarted" and `undelivered` empties; check `select started_at from tasks where number = N` before and after. Repeat with a `waiting` ticket: `assignments` should still have a single entry.

### 3. A second mention arrives on the same issue during the run

**What DSH does: delivers the message to the worker in progress. No Eval, no new ticket, no Decision.**

- The second mention arrives as a comment, through the notification (`dsh: src/sources/github.ts:344-374` and `intakeComments` at 384-403) or through polling the subscribed Threads (`github.ts:429-459`), in ≤ `pollSeconds`; `commentTrigger` marks `addressed: 'mention'` (`github-trigger.ts:65-76`).
- At intake (`dsh: src/core/intake.ts:19-62`): the ticket subscribed to `github:<n>` when it was born (`tickets.ts:52`), so the Trigger fans out (`intake.ts:34-52`) and becomes an Input via `addInput` (`tickets.ts:234-245`), which requests delivery to the executor. Since the live ticket owns the message (`model.ts:75-88`), it does **not** go to Eval (`intake.ts:56-58`). `docs/002-authorization.md:20-26`: the main session receives a follow-up notice and can only stop the work.
- Delivery (`dsh: src/executor/dsh.ts:290-343`) injects the message into the worker's session with `steer` (342), re-reading the ticket before each send. An idle worker (`waiting`) is woken in the extra slot reserved for people (`dsh.ts:305-309,171-199`). Worker `blocked`/`failed`: the human message raises `waitsForPerson` (`model.ts:349-353`) and is delivered (`tickets.ts:237-241` holds back only automatic Inputs).
- The worker decides: handle it within scope or return it with `orchestrator_trigger_handback` (`002:28-34`, `tickets.ts:106-115`); only then does the message go to Eval and can become another ticket on the same issue (the domain allows several tickets per Thread: `001:52`). Tests: `tests/core-engine.spec.ts:186-262` (fan-out) and `359-700` (follow-ups, owners and hand-back). There is no parallel in the SPEC: Symphony has no messages, only the issue state.

**What the board shows today.** Nothing changes in `ticket_state` (`sync.ex:481-491`): the overlay remains `running` (or `question`, if the agent's last comment asks, `board.ex:472-491`). The comment appears in the conversation after the 5 min sync (`sync.ex:83`). The board does not say that the message was delivered to the worker or whether the worker returned it. Since tasks are per issue number, no duplicate task is born.

**What the board should show.** A marker "follow-up entregue ao agente às HH:MM" ("follow-up delivered to the agent at HH:MM") (from `inputs[]` with `kind: trigger` and `human: true` after `startedAt`, `readAt` saying whether the worker has read it) and, if there is a hand-back (`disposition.handbacks`), "devolvido: <motivo>; aguardando avaliação" ("returned: <reason>; awaiting evaluation"). Never a second task for the same issue.

**Not verified.** The real latency and the mid-turn read. Experiment: with a `progress` ticket on issue N, comment "@sallaumen-agent também X" within scope; within ≤ 60 s, in SQLite, `$.inputs` gains `{kind: trigger, human: true, deliveredTo: <assignment atual>}` and `readAt` fills in on the worker's next step; the `disposition` table has `fanout = [ticket]` without `evalId`; the `decision` and `ticket` tables gain no row. Repeat with an out-of-scope request: `disposition.handbacks` gains the entry and `thread.pending` receives the Trigger; check whether a ticket is born whose `origin.triggerId` is that comment.

### 4. The ticket's PR is closed without merge by a person

**What DSH does: ends the ticket with `outcome: 'closed'`, keeps subscriptions, worktree and branch.**

- On every poll, `pollTicketPulls` reads the open tickets' PRs (`dsh: src/sources/github.ts:404-413`); `observePull` sees `state == 'closed'` without `merged` (`github-pull.ts:57-69`) and `closePull` reports `threadClosed(..., 'closed', closed_at)` (`github-pull.ts:80-84`).
- `Tickets.threadClosed` (`dsh: src/core/tickets.ts:77-90`) writes `follows[].closed`; if no own open PR remains (`followsDone`, 95-101) and the work is not unfinished (`unfinished`, 370-379: resume or retry after the close, or an accepted human follow-up with no later report), it calls `end(ticket, 'executor', 'closed', closed_at)` (345-363): every Assignment becomes `ended`, and `executor.stop` cancels the turn unless the last word was `ready`/`dropped` with no Input after, and kills the jobs (`dsh.ts:357-370`). Test: `tests/core-engine.spec.ts:1087-1116`; the "merge during accepted follow-up" branch at `541-559`.
- The Subscription stays (`github-pull.ts:77-79`, `001:37`): a human comment on the closed PR or on the issue resurrects the ticket under the same Mandate (`tickets.ts:252-270`, `intake.ts:40-46`), with the note `RESUMED` (`dsh.ts:132-135`). A reopened PR is followed again (`github-pull.ts:63-65`, `003:98`). No code removes the worktree (see case 1). The closure notice goes only to chat channels; on GitHub the PR already shows it (`github-pull.ts:90-105`). In the SPEC, the equivalent is the terminal state: stop and clean (`SPEC.md:803-811` §8.4, `831-839` §8.5).

**What the board shows today.** `ticket_state` only distinguishes `merged` (`sync.ex:484`); a `closed` ticket whose last report was `ready` falls into `"ready"` (`sync.ex:487`), so the 10 s poller keeps the task "para revisar" with a closed PR until the next sync. On sync, `reconcile_resolved_tasks` (`board.ex:96-121`) treats a `closed` PR the same as `merged` (`board.ex:81`): the task becomes `done`, whose label is "mesclado" (merged) (`board.ex:664`), and enters "Concluídas" (Completed) (`maintainer-contract.md:212`). The `closed` state exists in the list (`board/task.ex:9`) and nothing assigns it.

**What the board should show.** `closed` ("fechado sem merge", closed without merge), outside "Concluídas" and "Precisa de você", with the hint "um comentário na issue ou no PR retoma o ticket" ("a comment on the issue or the PR resumes the ticket") and the link to the leftover worktree (given to the workstream 4 cleanup script).

**Not verified.** The live sequence and the time until `ended`. Experiment: with a `ready` ticket whose `follows[]` has the PR with `own: true`, `gh pr close P`; within ≤ 60 s check `follows[].closed.outcome == 'closed'` and `ended == {by: executor, outcome: closed, at: <closed_at>}`; check `tasks.state` at 10 s ("ready") and after the sync ("done"); comment on the issue as a human and check that `ended` disappears and a `pending` Assignment is born.

## Summary

| Situation | DSH does | Board shows today | Board should show |
|---|---|---|---|
| Issue closed during the run | Nothing: does not read the issue's `state`; worker continues; ticket ends by whatever the worker reports; worktree and PR stay | "rodando", then "para revisar"; `done` only through a PR; with the board's Parar, "parado" while the agent runs | "agente continua em issue fechada; não foi parado" in Precisa de você; "parado" only with `ended.by == human` |
| Restart with a `running` Assignment | `resume` → Assignment ends `hostRestarted`, new `pending` with a recovery note in the same session and worktree; a `waiting`/`ready`/`blocked`/`failed` report with no new Input keeps the session | "rodando" during the outage; "Sem sinal" in the header after 120 s; `started_at` advances on restart | "agente fora do ar; retoma no reinício"; freshness confirms through the API; `started_at` of the first Assignment |
| Second mention on the same issue | Fan-out to the live worker as Input (`steer`); no Eval, ticket or Decision; the worker handles it or returns it | No state change; comment only after the sync | "follow-up entregue às HH:MM" / "devolvido: motivo"; never a second task |
| PR closed without merge | `threadClosed` → `ended.outcome == closed`; Assignments ended; subscriptions, worktree and branch stay; a human comment resumes | "para revisar" for up to 5 min, then `done` labeled "mesclado" and counted in Concluídas | `closed` ("fechado sem merge"), outside Concluídas, with "um comentário retoma" |

## Alternatives

| Alternative | Benefit | Cost or risk |
|---|---|---|
| Leave it as is: the board mirrors the last report | No change | False "parado", "mesclado" and "rodando" in cases 1, 4 and 2; when parallelizing, each case multiplies |
| The board starts writing to DSH (stop through the API) | Stop becomes real | Breaks "the board only reads" (`maintainer-contract.md:262`); requires the contract to change and the API to accept authenticated writes |
| The board derives the state from `ended.outcome` and orchestrator liveness, and says what it did not do (chosen) | Honest and read-only; fits the two-layer model | Does not solve the worker running on a closed issue: that is DSH's |
| Change DSH to reconcile a closed issue as the SPEC does (§8.5 B) and clean terminal worktrees | Closes the gap at the source | Outside this repository; remains an upstream suggestion |

## Decision

The rules below are the proposal for `docs/maintainer-contract.md`, section "The data" and a new section "The agent's lifecycle". This PR does not edit the contract.

1. **The task state follows `ended.outcome` when the ticket has ended:** `merged` → `done`; `closed` → `closed` (closed without merge; not counted in Concluídas); `stopped` → `stopped`; `completed` → `ready` with the note "sem PR" (without PR); `dropped` → the issue baseline with the note "o agente não fez nada" ("the agent did nothing"). Today only `merged` is read (`sync.ex:484`).
2. **A ticket is only "parado" when SQLite says `ended.by == "human"`.** The board's Parar closes the issue and marks the task; if the ticket remains alive, the task appears in Precisa de você with "o agente continua; o board não o parou" until the ticket ends. The write that this rule reserved for stop was not the first authorized: on 2026-11-07 the owner authorized the transient-failure retry (below). Stop through the API remains outside the contract.
3. **A `running` ticket with an unreachable orchestrator is "fora do ar", not "rodando".** Liveness comes from the API (`Orchestrator.load/0`) and the WAL mtime; the board says which of the two failed.
4. **`tasks.started_at` is the `startedAt` of the ticket's first Assignment**, never that of the resume or the retry.
5. **A second mention never creates a second task.** The board shows the follow-up from `inputs[]` (delivered, read, returned), without writing to SQLite.
6. **The sync updates an existing task's state when the issue closes** (`upsert_issue` starts replacing `state` in that case), respecting `stopped` and `archived`.

## Choice and consequence

The board remains a mirror (`maintainer-contract.md`, "Boundaries"): none of the rules above writes to SQLite or to the DSH API; the board's only write to the API is the automatic retry of the next section. What changes is what the mirror shows: the `outcome` instead of the last report, the process liveness instead of the mtime alone, and the truth about Parar. The gaps that only DSH closes, reconciling the closed issue (`SPEC.md:831-839`) and cleaning terminal worktrees (`SPEC.md:841-849`), are recorded here as a suggestion for the DSH repository; workstream 4 (cleanup script, `docs/research/symphony.md` §5) covers cleanup from outside in the meantime.

Side finding, for a separate issue: `scripts/agent/tickets.sh` reads `assignments[0]` and the board reads the last Assignment (`agent_state.ex:136`); after a restart or retry the script shows the old report (already noted in `docs/research/symphony.md` §5).

## Automatic retry (2026-11-07 amendment)

**Context.** After the 2026-11-07 reboot DSH came up without network: #50, #52 and #53 failed with `LlmError: DeepSeek Messages transport failed`, #54, #55 and #56 with `Could not resolve host: github.com` in `prepare`. All six stayed `failed` until a person called `POST tickets/<id>/retry` by hand. DSH only retries within the turn (`TRANSIENT_TRIES = 3`, `TRANSIENT_BACKOFF_MS = 15_000`, constants in `dsh: src/executor/dsh.ts:30`, no configuration; about two minutes in total) and deliberately refuses to retry a `prepare` that failed (`PrepareFailed`, `dsh.ts:40-43,278-280`), because a directory that was left with files would pass as a prepared worktree.

**Decision.** The owner authorized the board to call `POST tickets/<id>/retry`, and only that, with these limits (the binding text is in `docs/maintainer-contract.md`, "Automatic retry"):

1. Only the last Assignment, and only with a `failed` report read as transient (`AgentBoard.AgentFailure`: model transport, DNS, connection refused or dropped, timeout, rate limit, 5xx). Unknown text, refused credential, the runner's own deadline exceeded, and a `prepare` that left files in the directory need a person.
2. At most three retries per failure sequence, after 1, 5 and 15 minutes; the sequence counts the `endedReason: "retried"` from DSH itself, whoever requested it.
3. One retry per Assignment id, guaranteed by a row in `agent_retries` (unique index) written before the request; DSH's `canRetry` is the second lock.
4. Only when `GET /state` responds; nothing is sent with the orchestrator down.
5. Each request becomes an `agent_retry` (or `agent_retry_error`) event in the board and a log line.

**Preferred alternative, discarded.** Changing DSH to a configurable retry between Assignments would solve it at the source, but the prototype is not from this repository and the `prepare` retry is refused there for a valid reason that the board can check (the ticket's directory is empty or does not exist). It remains an upstream suggestion: expose `TRANSIENT_TRIES`/`TRANSIENT_BACKOFF_MS` in the settings and classify `LlmError ... transport failed` as transient: the text does not match `PASSING` (`dsh.ts:44-45`), so, without `status` or `code` in the original error, the failure was treated as final on the first attempt.

## Rollout and review

This PR: the ADR and the line in the index. Then, in separate PRs: (1) the rules in the contract; (2) `ticket_state/2` reading `closed`, `completed` and `dropped`, with tests in `sync_test.exs`; (3) the honest Parar; (4) liveness through the API in freshness; (5) `started_at` of the first Assignment; (6) `upsert_issue` with `state` on a closed issue. Before (2) to (6), run the four experiments above with a test ticket and note the result in this ADR. Reconsider when `executor.maxWorkers` rises above 1 and when DSH starts reconciling closed issues.
