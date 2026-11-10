# A task the owner answered goes back to work, 2026-11-10

Workflow: `async-state` (Elixir Agent Kit 0.8.0), medium.

## The report

arena-rogue #208 showed "Blocked". The owner answered at 14:44, the agent
replied "On it" at 14:45 and worked until 15:20. The card stayed "Blocked" for
those 35 minutes.

## Who owns the transition

| Transition | Owner | Evidence it reads |
|---|---|---|
| any → blocked / question | `Tickets.state/2`, written by the ticket poller (10 s) and the sync | the last Assignment's report (`waiting`, `blocked`) and the workpad |
| blocked / question → running | the same rule | **before:** only a new report. The owner's comment and the agent's reply were never inputs, and `waiting` was tested before "running" |
| | | **now:** the runner's own record that the worker read a person's message after that report (`inputs[]`: `kind: "trigger"`, `human: true`, `deliveredTo`, `readAt`) |

The runner's record for #208 (UTC): one Assignment; report `waiting` at
17:00:44; the owner's message at 17:45:11, read at 17:45:12; next report
(`ready`) at 18:20:31. `idleAt` stayed at 17:00:44 the whole time.

## The rule

A `waiting` or `blocked` report older than a person's message the worker read
no longer decides: the task is `running`. It decides again when the worker
writes a newer report (it asks again), goes idle after the answer, or the
ticket ends. A message not read yet, a machine's trigger, or a comment's text
("On it") change nothing. The board only reads; it asks nothing of the runner.

Two things follow the same fact: the card in Now says "Back to work: read your
answer at HH:MM", and the 15-minute silence clock counts from the answer
instead of from the old report (it would otherwise mark the task silent at once).

## Checked

Isolated server on a copy of the real data, with a throwaway runner state
holding one ticket in the shape of #208's:

- [01](01-before-answer-1920-dark-en.png): the waiting ticket puts #209 in Needs you as Blocked.
- [02](02-after-answer-1920-dark-en.png): the answer is recorded as read; within one poll, **without a reload**, the task is in Now, Needs you is empty and the header says "it is working on #209".
- [03](03-now-card-dark-en.png): the card.

Tests: the rule (`sync_test.exs`, six cases), the runner's JSON to the field
(`agent_state_test.exs`), sqlite to the task's state (`ticket_poller_test.exs`),
the silence clock (`agent_signal_test.exs`), the card (`board_stall_test.exs`).

## Not checked, not done

- Not seen against the live runner: no ticket is waiting right now. The JSON
  shape comes from 35 real trigger inputs in the runner's database.
- The card's clock still counts from the Assignment's start, waiting included.
- A Question that turns into Blocked when the agent posts a plain comment
  before any answer is unchanged.
