# Smaller truths (audit proposal P6), 2026-11-10

Workflow: `metrics-costs` (Elixir Agent Kit 0.8.0), small. Each row is a label
or a number whose origin or window the screen did not say.

| Shown | Source | Before | Now |
|---|---|---|---|
| CI of a merged PR in History | `PullRequest.checks_state` (GitHub Actions) | "CI failed: gates" in red, while the merge log said "Local CI passed" for the same PR | `Lanes.ci/2`, the merge log's answer: the local gate first; a red remote check alone is "Local CI unknown", with the remote failure in the hover |
| Remote check in a task's Activity | `PullRequest.checks_state` | "CI failed · gates", red | "GitHub Actions failed · gates", plain |
| Events in a task's Activity | `events` rows whose subject names the task | the raw kind (`task_released`); only what survived in the repository's last 50 events (arena-rogue logs about 5 000 sync rows for 17 releases); `#12` also matched `#123` | in words, both languages; the task's own newest 10, read by number |
| Calls count and total in the inspector | `ai_calls` of the task, newest 20 | "20 calls · total" even when the task had more | "newest 20 of 23 calls", and a line under the table saying the totals cover only those; the tab counts all |

Also: the table footer's "chamada/chamadas" was Portuguese in both languages.

## Checked

- [01](01-history-prs-1920-dark-en.png): History and the merge log behind it give the same words for the same PRs (copy of the real data; the rig has no runner state, so the live board shows more "Local CI passed").
- [02](02-activity-dark-en.png): Activity of arena-rogue #208 reads "Released to the agent".
- No task in the real data has more than 3 board calls: the 20-call note is covered by a LiveView test with 23 calls, not by a capture.

## Not changed

- The hover still says a red GitHub Actions check is "billing/no credit": that is the merge log's existing sentence, true for this account today.
- Events about a task's pull request (`pull_error #1422`) are not in the task's Activity.
