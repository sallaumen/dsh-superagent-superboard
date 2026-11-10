# A heads-up when a run passes the time its size allows, 2026-11-10

Workflow: `operational-alerts` (Elixir Agent Kit 0.8.0), medium.

## What existed

Only the silence: a running task with no signal for 15 minutes, whatever its
size. A task that keeps changing files never trips it, however long it runs.

## The item

| | |
|---|---|
| Condition | a `running` task whose work has lasted past its size's limit: S 20 min, M 40, L 60, no size 60 (`Lanes.slow_after/1`) |
| Identity | the task; one item per task (`slow-<id>`), and a task that is also silent shows only the silence |
| Clock | from `state_changed_at`, the moment the task last became `running`: a retry or the owner's answer starts it again, waiting is not work |
| Opens | on the first board reload after the limit (a ticket or worktree change, or the five-minute sync) |
| Says | "Taking long": since when it works, the limit that made it an item, the last signal when there is one. Never that the agent is stuck |
| Notifies | the voice, once, when the item first appears (ten phrases per language) |
| Closes | when the task leaves `running`. Derived on each read, written nowhere, nothing to acknowledge |
| Place | last in Needs you, in the stale tone: it asks nothing yet |

Small and large are the owner's numbers; medium (40) and no size (60) are the
defaults he accepted. Of the last week's 125 tasks, 47 had no size.

Also here: a silence that began with the owner's answer says "The agent read
your answer at HH:MM; no signal since then" instead of calling the answer a report.

## Checked

Isolated server on a copy of the real data, with two tasks set to `running`
34 minutes earlier, one small (#209) and one large (#208), and one question:

- [01](01-needs-1920-dark-en.png): the small one is "Taking long", after the question; the large one is not listed.
- [02](02-needs-item-dark-en.png), [03](03-needs-390-light-pt.png): the item, English dark and Portuguese light at 390 px, no horizontal overflow; its button opens the task.

## Not done

- No timer: a task with no ticket or worktree change shows the item up to five minutes late.
- The Attention bell in the top bar still counts only blocked, question and review (it never counted silences either).
- The Now card itself does not change; its clock still counts from the Assignment's start.
- The limits are constants in `Lanes`, not a setting.
