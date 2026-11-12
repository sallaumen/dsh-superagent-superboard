# Motion: Settings → Costs charts (CostsMotion)

Isolated server: the copy of the dev database (`agent_board_motion`, migrated
to today's main, 80c0803) on port 4613, fake orchestrator, no keys. Headless
WebKit at 1440 × 1700 so the whole dialog fits. `Element.prototype.animate`
was wrapped from the first script on, so the sweep on opening is caught too;
the animations were paused and seeked frame by frame.

Before this change the chart and the tiles cut to the new reading: opening the
section, or going from 30 to 7 days, swapped the bars in one frame.

| Capture | Step | What it shows | Measured |
|---|---|---|---|
| `01-open-30-days-sheet.png` (0, 71, 142, 354 ms) | open Settings → Costs, 30 days | the days with spend rise from the baseline in one sweep, left to right; the stacked day (agent + board AI) grows as one bar | 9 segments; the last one ends at 354 ms; `kit.reveal` |
| `02-window-30-to-7-sheet.png` (67, 133, 216, 333 ms) | click "7 days" | the seven bars rise in turn, the same 240 ms sweep spread over seven | 7 segments; the tiles whose value changed (`costs-agent`, `costs-board`, `costs-claude`) got `is-changed`; `?` (Codex) and `—` (ElevenLabs) did not |
| — | a `:board_updated` broadcast with the section open | one more patch, `data-motion-view` unchanged | no animation inside `#settings-costs` |
| `03-reduced-motion-7-to-30.png` | `prefers-reduced-motion: reduce`, click "30 days" | the 30 bars, at once | no animation |

Found while capturing: with two spent days in a 30-day window, the first
version waited 240 ms before those bars rose, because the sweep counted the
empty days. The sweep now spreads over the days that have a bar.

Not observed: the voice chart (`#costs-voice-daily`, the copy has no voice
requests; same code path), a meter (no tile in this data has one), a reloading
calls or voice filter, dark theme, phone width.
