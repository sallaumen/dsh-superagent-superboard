# Motion: values that changed (ValueChange)

Same isolated server as `../motion-lanes` (copy `agent_board_motion`, port
4613, fake orchestrator, broadcasts by `rpc`), headless WebKit at 1440 px.
CSS and Web Animations were paused as they started and seeked frame by frame;
a `phx:update` counter confirmed one patch per step.

Before this change: the lane counts and the inbox badges cut to their new
value, and the sparkline's current-hour bar jumped to its new height.

| Capture | Step | What it shows | Measured |
|---|---|---|---|
| `01-queue-count-and-attention-badge-sheet.png` (rows: 0, 70, 140, 300, 600 ms) | #228 queued → question | Fila's count goes 2 → 1 and tints; the Attention badge goes 2 → 3 and bumps (rows 2–3) | count color read with `getComputedStyle` while seeking: `rgb(44,106,77)` (`--agent`) at 0 ms → 59,100,77 → 77,92,77 → 88,88,77 → `rgb(92,86,77)` (`--ink-muted`) at 600 ms; badge `ab-count-bump` 200 ms |
| — | same step | Precisa de você stayed at 4 (the "no answer" need became a question need), so its count did **not** tint | `is-changed` absent |
| `02-spark-zoom.png` (0, 30, 60, 100, 180 ms), `02-spark-tile-after.png` | PR #243 merged now | the current-hour bar of "PRs merged" grows from its base, 7 → 10 px | Web Animation 180 ms, `scaleY(0.7)` → none, `m3.standard` |
| — | reduced motion: #228 back to the queue and PR #244 merged | counts and bar updated; `document.getAnimations()` empty | no animation |

Found while capturing: the current hour's bar title ends at the minute it was
computed (`19:00–19:48: 2`), so the hook compares only the hour's start;
comparing the whole label would have turned every growth into a cut.

Not observed: a Messages badge rise (needs a real GitHub message; the same
code path as Attention), the first bar of a new hour (a cut by design), dark
theme, phone width.
