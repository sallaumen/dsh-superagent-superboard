# Audit: health and data truthfulness

> **Historical record — November 5, 2026.** Counts, captures and states
> describe the revisions identified in this document, not the current product.
> See the [audit index and sequence](README.md).

Baseline `7883316` (#158). Real data was only read; no writes to tasks.

| Severity | Region | Evidence before | Fix |
|---|---|---|---|
| P1 | Sync health | [Before](layout-after-1366.png): “no sync yet” despite a recurring `sync_error`. `last_sync/1` looked only for `sync` in the 20-event window. | Dedicated query for the last `sync`/`sync_error`; failures prevail over a previous success, identify the saved data and open Activity. Dates with day and explicit UTC. |
| P1 | Reconnection | [Before](baseline-disconnected.png): “live” continued after the disconnect. | State updated by the client connection events, without depending on a new server render. |
| P2 | Merged / Speak | `Board.board_for/1` limits merges to 30; the UI looked like it showed the total. `Voice.summary/2` ignored `blocked` and called an only-blocked board calm. | “latest N” in the counter, “recent merges” in the speech, blocks included. |

After: [health](health-after.png), [activity opened by the status](health-activity.png),
[disconnected](health-disconnected.png). WebKit confirmed `live → reconnecting → live`
via LiveSocket disconnect/connect. Data and network calls were not changed.
Zero console errors.

Tests added: sync beyond the 20-event window, a failure after the last success and the
summary of an only-blocked board. Local gate `scripts/ci-local.sh all` green
(154 Elixir tests; asset checks/build/deploy; validator and 20 library tests).
CI blocked by billing as reported; workflow_dispatch after release.
