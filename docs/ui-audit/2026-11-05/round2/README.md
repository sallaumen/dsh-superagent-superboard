# Agent Board — second visual review

Base: main `be2c29c`, pulled before work through its existing worktree. The review
used the real app at 127.0.0.1:4002 (`mix setup` then `mix phx.server`, PORT=4002)
and guarded rollback-scoped fixtures at localhost:4004. Postgres: 127.0.0.1:5434.
The data/AI/domain modules under `lib/agent_board/` were not changed.

The identity remains monospace, dense and token-based. The board is the primary
surface; secondary tools open on demand. Socket liveness is distinct from stored
data freshness. Components own presentation; BoardLive owns existing actions.

| Severity | Region | Evidence | Correction / PR theme |
|---|---|---|---|
| P1 | Reconnection | [Panel evidence](03-panels.md), regression test for repository recovery | Same repository selection is a no-op; recovery retains panel/draft/focus. |
| P1 | Data freshness | [Before/after](02-freshness.md) | Last completed sync delayed at 2 min, stale at 5; failed-attempt time is not presented as refreshed data. |
| P1 | Native modal state | [Browser findings](03-panels.md) | Preserve native open state through LiveView patches; close via dialog API so the board does not stay inert. |
| P2 | Component size / identity | [Extraction](01-components.md) | Separate LiveComponents, one per region; stable card IDs. BoardLive 835 → 398 lines after extraction, 463 after all features. |
| P2 | Density / history / keyboard | [Panels](03-panels.md) | Activity, conversation/details, Split and AI open in place. Back/Forward/Escape and return focus; no ghost history entries. |
| P2 | Icons / motion / flash | [Feedback](04-feedback.md) | Text plus semantic Heroicons; 120 ms optional entry, no animation on broadcasts, reduced motion, visible modal flash. |

Delivery order: components (#173) → data age (#177) → panels (#182) → feedback (#183).
Each PR is based on the preceding branch so its diff contains one theme. The older
#171 design pass is outside this stack and overlaps the refactored view; it must be
adapted to the components before integrating it after this stack. No PR was merged
as part of this review.

## Coverage and limits

- Browser available: WebKit headless. **No item remains unverified because a browser
  was unavailable; no fallback browser test is pending.**
- Verified: before/after screenshots per visual phase, both themes, desktop/mobile/
  ultrawide, native dialogs, URL history, keyboard focus, draft preservation,
  disconnect/reconnect, stable DOM during broadcasts, loading, flash and reduced motion.
- Poller: existing tests cover real 10-second scheduling, overlay and idempotence;
  fixture broadcasts/movement were observed in the browser. The real runner's
  SQLite was not changed to provoke a state transition.
- Real creates/stops/archives/messages/paid AI were not exercised, by instruction.
  Existing automated tests with stubs still pass. The fixture's offline adapter
  prevents a paid AI request during its error-feedback check.
- The backend exposes no reliable last successful runner-poll timestamp, and a
  sync_error does not establish the age of saved data. Those facts are not guessed.
- The earlier billing blocker still makes local gates authoritative; all commands,
  counts and full logs are recorded in the individual PR evidence files.
