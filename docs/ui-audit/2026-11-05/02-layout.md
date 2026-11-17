# Audit: density, responsiveness and readability

> **Historical record — November 5, 2026.** Counts, captures and states
> describe the revisions identified in this document, not the current product.
> See the [audit index and sequence](README.md).

Continuation of 01-theme; baseline `80e3ee9` (#154). Same direction and constraints.

| Severity | Region | Evidence before | Fix |
|---|---|---|---|
| P2 | Columns and hierarchy | 1366, 3440: 30 merges stretch the whole page, leaving four columns practically empty and hiding actions. | Columns with their own scroll (55vh on desktop), fixed headers and keyboard focus. Activity in a native disclosure, with a limited, scrollable list. |
| P2 | Titles | Before: titles truncated to a single line, especially at laptop width. | Word breaking and the full title; the five columns kept. |
| P2 | Mobile / activity / AI | Before, layout at 375px, fixture: the 375px page had scrollWidth 664px; rigid rows overlapped. | Cohesive control groups, an adaptive grid for events, AI with wrap, shrinkable fields. |
| P2 | Open / conversation | Before: conversation below Activity, Split and AI. | Conversation right after the board; the title receives focus on mount, Close restores the focus of Open. |
| P3 | Empty | `board_live.ex`: the instruction “Track one below” and “four columns” contradicted the screen. | Guidance to the header and five columns. |

After: 1366×768, 3440×1440,
375×812, dark,
mobile Activity,
desktop fixture, mobile fixture.
Full-page captures use the viewport width; their height may exceed the viewport.

WebKit: scrollWidth equal to the viewport at 1366, 3440 and 375 (including fixture).
At 1366, the page height fell from ~3050 to 930px and Split starts at y≈658.
The disclosure opens by native interaction; fixtures only verify presentation.
The interactive conversation is covered by the LiveView tests; no Open existed in the
real local data and no task was created for the audit.

Gate: `scripts/ci-local.sh all` green; 151 Elixir tests, zero failures; asset checks,
build/deploy, validator and 20 library tests green. CI blocked by billing;
local gate sufficient per PIPELINES.md. No merge/deploy.
