# Visual defects — 2026-11-10

Fixes for the defects a design critique found on `origin/main` 40c8b5f. Each
fix was measured and photographed on an isolated dev server of the worktree
(a copy of the dev database with lane states seeded into the copy only, no
keys, runner and superagents disconnected), driven with the Playwright MCP
(headless WebKit, one tab). Each image is before on the left, after on the
right, same viewport and state.

## 1. The Messages/Attention bar covered content

| What | Before | After |
|---|---|---|
| Inspector at 1440 × 900: bar against the task header | bar painted over the title's first line, the status, the id and Esc | inspector above the bar; header fully visible |
| Board scrolled 420 px at 1440: content around the bar | text visible left of a 440 px block and in the 24 px above it | one opaque band from edge to edge |

- `1-inspector-1440-before-after.jpg`
- `1-scrolled-1440-before-after.jpg`

Also checked after the change: the inspector at 1100 (floating) and 1920
(docked), dark at 1440, the scrolled board at 390, and the Messages menu
opening. No horizontal scroll at any of them.

## 2. Settings forms out of line

| What | Before | After |
|---|---|---|
| Section list: "Execution" beside "Codex 94%" | label squeezed to 51.9 px of its 59, 0.3 px from the hint | label whole, 16 px gap; still clear at "Codex 100%" (9 px) |
| System: Theme beside Board language | Theme heading stretched to 43 px, its control 26 px lower, segments 66 px tall | both headings 17 px, both controls on one line, segments 40 px |
| Add project: hint "Empty uses ~/projects/project-name." | under Owner, a column away from its field | under Local folder |
| Add project: agents stepper | buttons 26 px beside a 36 px input, plus the native spinner | all three 36 px (44 px on a phone), no spinner |
| Expanded project: "Check" beside the GitHub login | 26 px beside 36 px | both 36 px |
| Project rows: profile name | "superagent-dsh-superag…" cut; one row inline, two stacked | whole name, wrapped; every row stacked the same way |
| Voice language select | 384 × 20 px among 40 px fields | 40 px, with the board's own arrow |
| Volume and Speed | "35%" 7 px before "Speed" | each value beside its own label, 24 px between the two |
| Volume and Speed on a phone | sliders stop at 256 px of 322 | full width |
| "Every day at" | pale border and sunk fill from an old rule | the same border and fill as every other field |
| Titles | "Voice and summary" 13 px, the others 17 px; headings of 13, 14 and 15 px on System; "Add project" 13 px muted | section titles 17 px, headings below them 14 px |
| Execution chart | day labels under the tallest bars pushed down and clipped to 10.6 px | every label 14 px on one line |
| The board's own AI calls | mono cell 2.7 px lower than the text cells | one baseline |
| Section list at 390 | one row with 0.6 px to spare: a count or the update dot scrolled it | two rows of two; a count and the dot fit |

- `2-voice-1440-before-after.jpg`
- `2-system-1440-before-after.jpg`
- `2-projects-1440-before-after.jpg`
- `2-execution-1440-before-after.jpg`
- `2-nav-390-before-after.jpg`

Three of these came from old rules in `app.css` that load after `board.css`
and overrode it (the select, "Every day at", the 13 px titles and the slider
width); those rules are deleted rather than overridden again.

The System pictures differ in the version card ("Up to date" / "restart
pending") only because the worktree's branch moved between the two captures.
The count and the update dot on the phone section list were added in the
browser to stress the layout; the server did not have that state.

Also checked after the change: the Voice column in dark, the expanded project
row at 1440 and 390, and Projects, Voice and Execution at 390 with no
horizontal scroll inside the dialog.

## 3. Three dialogs on another design system

Split request, Merge History and Voice conversation were still painted by the
daisyUI theme (a cold blue palette of its own) and by old rules in `app.css`.
DESIGN.md already says how that theme maps to the board tokens; the map is
now applied, so every old rule that reads a daisyUI colour follows the tokens.

| What | Before | After |
|---|---|---|
| Split request: submit | ink on cold blue, 2.18:1 in light and 1.72:1 in dark, 16 px radius, 44 px | the board's primary button: white on `you`, 6 px radius, 40 px |
| Split request: field | 16 px radius on a sunk fill | 6 px radius, `line-strong` border, `surface` fill |
| Split request: proposal | "OBJECTIVE", "OPEN QUESTIONS" in 10 px capitals; "Create" as 10 px text in a hairline box | 12 px labels in normal case; "Create" is a button |
| Merge History: heading and signals | "MERGED PRS", "NO REVIEW", "CI FAILED: GATES" in 10 px spaced capitals, system mono | "Merged PRs" 14 px; "no review", "CI failed: gates" 11.5 px Plex Mono |
| Merge History in dark | cold navy band and bars | warm paper tones |
| Voice conversation | pill Close (75 x 40, no border), pill field, pill Send and Write, 22 px dialog radius, 18 px bubbles | the shared Close (77 x 32), 6 px field and buttons, the shared dialog radius, 10 px bubbles |
| Scrim in dark | lightened the page (it mixed in `ink`, which is light in dark) | darkens it |

- `3-split-and-history-1440-before-after.jpg`
- `3-voice-1440-before-after.jpg`
- `3-dark-scrim-1440-before-after.jpg`

Also checked after the change: the board and the inspector in light and dark
(unchanged), and a split on the isolated server (rehearsal answers, copy
database) to see the proposal.

Left as it is: the composer keeps its own compact header (an icon button
beside the Esc key), and the last visible row of Merge History is cut by the
dialog edge because the list scrolls there.
