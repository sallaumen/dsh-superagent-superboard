# Motion: cards that change place (BoardMotion)

Isolated server: a copy of the dev database (`agent_board_motion`) on port
4613, `AGENT_BOARD_ENV_FILE=/dev/null`, auto-retry and auto-release off, a fake
orchestrator on 4614, an empty `state_db`, superagent ticks manual. Lane states
were changed by SQL on the copy and each step was announced with one
`:board_updated` broadcast (`Phoenix.PubSub` over `rpc`). Headless WebKit
(Playwright MCP), 1440 px wide.

Method: `Element.prototype.animate` was wrapped to pause each new animation,
then every animation was seeked to the same time and the viewport was shot.
Each sheet stacks four of those frames, top to bottom. A `phx:update` counter
confirmed one patch per step.

Before this change every one of these steps was a cut: the card disappeared
from one lane and was in the other on the next frame (the first and last frame
of each sheet, with nothing between).

| Sheet | Step | What the frames show | Measured |
|---|---|---|---|
| `01-queue-to-now-sheet.png` | #229 queued → running | the card leaves Fila (right), travels over Agora on a bent path and lands on top; #225 slides down to make room | traveller 409 ms, x `kit.land`, y `m3.emphasizedDecelerate`; room-making 146–159 ms |
| `02-now-to-needs-sheet.png` | #225 running → question | the card leaves Agora and travels down to the end of Precisa de você | 370 ms; the neighbour 159 ms |
| `03-arrives-in-queue-sheet.png` | #222 back to the queue | the new row fades in and rises 6 px in its slot; nothing else in Fila moves | 40 ms delay, 140 ms opacity, 94 ms rise |
| `04-leaves-and-merge-dot-sheet.png`, `04-merge-dot-zoom.png` | #225 done, PR #242 merged | the old card fades where it stood (130 ms, `kit.leave`) and today's twelfth dot scales in 90 ms later (280 ms, outBack) | see the zoom: rows 1–2 eleven dots, row 3 the new one growing, rows 4–5 settled |
| `05-reduced-motion-cut.png` | #227 queued → running with `prefers-reduced-motion: reduce` | the state after the patch; `document.getAnimations()` was empty | no animation, state correct |

Also observed: a broadcast with no change (`select 1` + `:board_updated`)
started no animation; switching to o_colmex (scope 1 → 2) started none either.

Capture artefact, not behaviour: in the last frames of sheet 04 the leaving
card still shows at full opacity. Seeking a paused animation past its end
neither applies a fill nor fires `finish`, so the ghost is not removed in the
capture; in playback `finish` removes it after 130 ms.

Not observed: a phone width (the lanes fold there; hidden cards are skipped by
the zero-rect check but this was not stepped through), the dark theme, a real
socket reconnect, and a patch arriving mid-travel (handled by cancelling and
re-measuring; covered only by reading the code).
