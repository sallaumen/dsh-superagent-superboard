# What each ended task cost, on its row, 2026-11-10

Workflow: `metrics-costs` (Elixir Agent Kit 0.8.0), large. Audit proposal P3b,
the owner's choice.

## Metric definition

| Shown | Source rows | Window | Unit | Rule | Exclusions |
|---|---|---|---|---|---|
| executor cost of an ended task (History → Ended tasks) | `usage_ledger`, attributed as the Executions tab does (`Usage.Report.executions/2`: exact for a harness ticket, then PR link, then branch) | last 90 UTC days | US$ per executor, never summed across: DeepSeek `≈` (estimate) or `≥` (cache reads have no price), Claude Code list price, Codex "cost unknown" | sum of the priced executions of that executor | executions with no task; the board's own model calls (they stay in the task's inspector) |

No new table: the ledger is already stored. `Usage.TaskCosts.refresh/1` runs
after each ledger refresh (`Usage.Worker`, five minutes) and keeps the result
in memory; a render reads a map. After a boot, until the first run, a row
shows "—" and its tooltip says the value is not computed yet. A task with no
attributed execution in the window is "—" too. Never a zero.

## Traced by hand

arena-rogue #208 (task 52892), on a copy of the dev database and of the
runner's state:

| Where | Value |
|---|---|
| its row (`TaskCosts`) | DeepSeek, 1 execution, 148 392 micro-US$, incomplete → "≥ US$ 0.14" |
| the Executions tab (`Report.by_task/2`) | the same execution, 148 392, incomplete |
| the inspector header (`Harness.for_tickets/2`, the transcripts) | 148 392, incomplete |

The refresh took 2.1 s over the copy's 90 days (4 144 Claude Code, 1 536 Codex
and 203 DeepSeek ledger rows), off the board's render path.

## Checked

- [01](01-history-ended-1920-dark-en.png): arena-rogue, 49 of 50 rows priced (all DeepSeek, all floors), 1 "—".
- [02](02-history-ended-390-light-pt.png): phone, Portuguese, no horizontal overflow.
- o_colmex and dsh-superagent-superboard show "—" in the rig: only the arena-rogue runner's state was copied. The live board reads every superagent's state.

## Not done

- The merge log rows on the main board, and the PR rows in History: a PR shows nothing yet.
- DeepSeek stays a floor until cache reads have a price (P3c).
- Not reconciled against a provider invoice or console.
