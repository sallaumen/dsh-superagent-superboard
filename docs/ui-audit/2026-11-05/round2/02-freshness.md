# 2 — Data age independent of socket health

| Severity | Region | Evidence | Correction |
|---|---|---|---|
| P1 | Header | [Before: socket live with a ten-minute-old completed sync](02-before.png); [after](02-after.png) | Last completed sync has locally advancing age. Delayed at 2 minutes; stale at 5 minutes, using warning/error tokens plus text. Thresholds reflect the one-minute sync cadence. |
| P1 | Failed sync | [Saved data](02-saved-data.png) | The error timestamp is labeled last attempt, never last refresh. Saved-data age stays unknown; existing dated sync failure remains visible. |
| P2 | Record age | [After](02-after.png), `board_components/data_age.ex` | Task/pull, activity, comment and AI timestamps carry a relative age plus full UTC date in title/datetime. Old activity alone does not imply unhealthy sync. |

The age hook uses the server clock plus monotonic elapsed browser time, updates
every 15 seconds and on tab visibility, and cleans up its timer. It performs no
network/database polling and does not rerender or focus controls. Missing/future
timestamps cannot look fresh. This does not invent a runner heartbeat: the domain
exposes a poller but no reliable last-successful-poll timestamp.

WebKit verified stale state on isolated test records; real stored data at port
4002 showed a sync failure with unknown saved-data age. [375 px](02-mobile.png)
has no horizontal overflow. Browser closed. Only unsent input text and read-only
operations; no actual tasks/messages created.

A broadcast on the isolated fixture retained exactly the same input/card DOM
nodes, text and focus, with unique card IDs. Poller cadence/idempotence remains
covered by `test/agent_board/live_test.exs` in the full gate.

`scripts/ci-local.sh all`: exit 0, 170 Elixir tests, strict checks, Sobelow,
check_assets, assets.build/deploy, library validator and 20 tests.
`node --test test/assets/data_age_test.mjs`: 3 tests passed, covering 2/5-minute
boundaries, missing/future timestamps and the distinction from ordinary activity.
[Pipeline log](02-gate.log), [JS test log](02-node.log).
Billing blocks CI; local evidence is the sufficient gate per PIPELINES.md.
