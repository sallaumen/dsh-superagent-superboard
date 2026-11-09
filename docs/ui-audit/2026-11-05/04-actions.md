# Audit: actions and feedback

> **Historical record — November 5, 2026.** Counts, captures and states
> describe the revisions identified in this document, not the current product.
> See the [audit index and sequence](README.md).

Baseline `67029d2` (#161). Audit close on 2026-11-05.

| Severity | Region | Evidence before | Fix |
|---|---|---|---|
| P1 | Create / flash | `board_live.ex` in the baseline, lines 133–135: the result of `Board.create_task` discarded before announcing “Task created”. [Fixture before](baseline-fixture.png) also shows the same error twice. | Handle success/error; the error appears once in the shared flash, with guidance. Tests with simulated GitHub cover 422 and success. [After](actions-after-fixture.png). |
| P1 | Conversation / repo switch | `load/2` loaded a new repo without clearing `conversation`, `comments` or `intake`; `handle_info` did not reload the conversation comments. | Clear the context on switch and update the conversation on broadcasts. [Open after](actions-conversation.png), [another empty repo](actions-empty.png). |
| P2 | Split / AI unavailable | [Before](layout-after-1366.png): Split enabled with `not_configured`; no loading feedback of its own. | Disable with an explanation, announce “Splitting…” during submit, update the call list on completion. [After](actions-after.png). |
| P2 | AI panel | `AI.recent/1` is global; `logged_in` only checks configuration; rehearsal also said logged_in. Empty list not explained. | Show “all repositories”, recent window, explicit empty, “configured · connection not verified” and “rehearsal · local fixtures”. No claim of validated authentication. |
| P2 | Speak / Dictate | `assets/js/app.js` returned silently when the API did not exist. “Speak” in the conversation spoke the board, not the conversation. | Feedback region and the label “Speak board status”; errors/unavailability announced. [Speak](actions-speak.png), [API missing](actions-speech-unavailable.png). |
| P2 | Stop / Archive | `board_live.ex` had buttons with no in-transit state and no explanation of the effect. | `Stopping…`/`Archiving…`, blocking while in transit and a title explaining closing the issue versus hiding it on the board. Not triggered on real tasks. |

Extra interactive verification: temporary `MIX_ENV=test` server on `localhost:4005`,
with fixtures in a single Ecto Sandbox transaction (rollback on shutdown).
Open by keyboard focused `conversation-title`; Close returned focus to the original Open;
switching repository removed the conversation. No creation, Stop, Archive or message send
was triggered in the browser. Speak was captured by a silent substitute for the audio API;
text received: “1 running and 1 blocked”. The microphone was not opened.
An initial attempt through the 127.0.0.1 host was rejected by the test environment's
check_origin; using localhost solved it. There was no change to the origin protection.

Final gate: `scripts/ci-local.sh all` green, including `MIX_ENV=test mix gate`
(158 tests, zero failures), `scripts/check_assets.sh`, `mix assets.build`, assets.deploy,
validator and 20 library tests. CI blocked by billing as reported;
the local evidence is sufficient per PIPELINES.md. No PR was merged.

## Final coverage matrix

| Area | Result | Evidence / limit |
|---|---|---|
| 1366×768, light and dark | Verified | [light](final-light-1366.png), [dark](final-dark-1366.png); no overflow, active connection |
| 3440×1440, light and dark | Verified | [light](final-light-3440.png), [dark](final-dark-3440.png); no overflow |
| 375×812 extra | Verified | [light](final-light-375.png), [dark](final-dark-375.png); scrollWidth=375 |
| Theme / persistence / system / keyboard | Verified | PR #154; real toggle, reload, prefers-color-scheme and focus |
| Contrast | Samples fixed | [measurements](final-contrast.txt): primary 5.38/5.36; semantic text over base100 between 5.99 and 7.38 in light, 6.19 and 7.11 in dark. Not equivalent to full WCAG certification. |
| Connection / reconnection / sync_error | Verified | PR #161; disconnect/connect + Activity; zero errors in the app console |
| Empty / no repo / no comments | Verified | Empty and no comments in the test browser; no-repo covered by LiveViewTest |
| Flash success/error | Verified in tests | Create with simulated responses; visual error by rendered fixture |
| Loading of mutating actions | Verified by code | phx-disable-with and LiveView blocking; no real submission and no paid call |
| Split result / AI list | Verified in tests | Req.Test simulates both calls, shows the proposal and updates the history; no real task created |
| Open / Close / repo switch | Verified in the browser | Transactional fixtures; focus, return and context removal |
| Stop / Archive | Existing code and tests | Board.stop_task/2 and archive_task/1; not executed in the browser |
| Speak | Verified without playback | Real LiveView event received by a substitute API; real sound not evaluated |
| Dictate | Unavailability verified | Feedback with missing APIs; real recognition and microphone permissions not evaluated |
| Screen reader | Not run | Accessibility tree, names, aria-live and keyboard inspected; no real assistive reader used |

Operational limit: the local sync of `sallaumen/o_colmex` keeps receiving GitHub HTTP
404. The audit fixed the signalling and preserved the saved data; it did not change
credentials/permissions nor try to fix repository access.

The audit's browsers and temporary servers were closed; the pre-existing server
on port 4002 was preserved. Captures identified as fixture are synthetic, with no
persisted data or external calls.
