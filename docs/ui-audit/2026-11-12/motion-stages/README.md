# Motion: a run's stage advancing, and the inspector opening

Isolated server: a fresh copy of the dev database (`agent_board_motion`) on
port 4613, fake orchestrator, and a runner state database (`state_db`) holding
one ticket for #229, shaped like the `board_stall_test` fixture. The stage was
advanced by giving that ticket an own PR thread (`follows: github:250`); the
board's 10 s ticket read picked it up. Headless WebKit at 1440 × 900; CSS
animations paused as they started and seeked frame by frame.

Before this change: the stage label cut from Análise to PR, and the inspector
appeared in one frame.

| Capture | Step | What it shows | Measured |
|---|---|---|---|
| `01-stage-to-pr-zoom.png` (rows: 0, 60, 120, 200, 290 ms), `01-stage-card-after.png` | #229's ticket gains its PR: done stages 0 → 2 | the line into "PR #250" draws from the left in `--agent` and settles to the rule colour; the stage's dot lands 90 ms after, with a small overshoot (row 4) | `ab-phase-draw` 200 ms; `ab-phase-arrive` 90 + 200 ms |
| `02-inspector-opens-sheet.png` (0, 40, 90, 200 ms) | click #229's title | the panel slides 24 px in from the right, opaque | `insp-enter` 200 ms |
| — | another task opened while the panel is open (#228) | `data-task-id` changes, the node stays | no `insp-enter` started |
| — | a `:board_updated` broadcast with the same stage | one more patch | no `ab-phase-*` started |
| — | `prefers-reduced-motion: reduce` | panel opens and stage shows at once | computed `animation-name: none` on the panel, the line and the dot; no `animationstart` |

Found while capturing:

- The first stage capture showed `data-value` going 0 → 2 with no
  animation: a second patch right after the change re-rendered `.ab-phases`
  with the server's class and removed `is-changed is-up`. The page's
  `onBeforeElUpdated` now keeps those two marks on a `[data-key]` element, so
  a close second patch no longer cuts any ValueChange pulse (lane counts and
  badges included).
- The first inspector entrance faded opacity. At this width the inspector is
  an overlay, and the translucent panel showed the board's text through it.
  It now slides in opaque.

Not observed: Análise → Código (the board reads it from the worktree's
changes, which the fake ticket has none of), phone width (the inspector covers
the screen there), dark theme.
