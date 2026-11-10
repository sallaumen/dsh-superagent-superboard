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
