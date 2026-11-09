# UI audits — historical evidence

> **Historical record.** Counts, captures and states describe the revisions
> from the time of the audit, not the current product.

Each round records the baseline, the method (headless WebKit, isolated fixtures) and
the local gate that passed. Captures without a report of their own are named here so
they are not lost.

## 2026-11-05 — main audit and parallel passes

The [main audit](2026-11-05/README.md) ran in four chained PRs, with a report and
captures per part:

- [01 — theme, tokens, contrast and focus](2026-11-05/01-theme.md)
- [02 — density, titles, Activity and responsiveness](2026-11-05/02-layout.md)
- [03 — health, reconnection and truthful counts](2026-11-05/03-health.md)
- [04 — success/error, conversation context, AI and voice](2026-11-05/04-actions.md)
- [05 — review for integration](2026-11-05/05-merge-review.md)

Specific passes, each with its own report:

| Folder | What it reviewed |
|---|---|
| [design-pass](2026-11-05/design-pass/README.md) | Layout adaptation to the current LiveComponents (after #173→#183) |
| [round2](2026-11-05/round2/README.md) | Second visual review on the real app (components, freshness, panels, feedback) |
| [soft-pass](2026-11-05/soft-pass/01-foundation.md) | Visual foundation ([02 — surfaces](2026-11-05/soft-pass/02-surfaces.md), [03 — AI cost](2026-11-05/soft-pass/03-ai-cost.md)) |
| [parallel-pass/reconnect](2026-11-05/parallel-pass/reconnect/README.md) | Reconnection in depth |
| [parallel-pass/cards](2026-11-05/parallel-pass/cards/) | Cards (paired captures) |
| [parallel-pass/css-cleanup](2026-11-05/parallel-pass/css-cleanup/) | CSS cleanup (paired captures) |
| [parallel-pass/settings](2026-11-05/parallel-pass/settings/) | Settings menu (paired captures) |
| [empty-board-history](2026-11-05/empty-board-history/README.md) | Empty lanes and merged PR history |
| [header-panels](2026-11-05/header-panels/README.md) | Header panels |
| [intake-readiness](2026-11-05/intake-readiness/README.md) | Intake readiness gate |
| [voice-command](2026-11-05/voice-command/README.md) | Voice capture by double Space |
| [voice-actions](2026-11-05/voice-actions/README.md) | Voice action confirmation |
| [voice-answer](2026-11-05/voice-answer/README.md) | Natural answer from the board |
| [voice-ask-shortcut](2026-11-05/voice-ask-shortcut/README.md) | Voice shortcut in the task conversation |
| [voice-intake](2026-11-05/voice-intake/README.md) | Voice intake draft |
| [voice-presence](2026-11-05/voice-presence/README.md) | Voice presence indicator |
| [voice-read-commands](2026-11-05/voice-read-commands/README.md) | Read-only voice commands (PR #223) |
| [voice-final](2026-11-05/voice-final/README.md) | Integrated voice UX battery |

Folders with captures only (no report): `attention-menu`, `create-panel`,
`fixed-scroll`, `merge-trend`, `merged-pagination`, `settings-menu`,
`task-pagination`.

## 2026-11-06 — focused rounds

| Folder | What it reviewed |
|---|---|
| [ai-failure-reasons](2026-11-06/ai-failure-reasons/README.md) | Failure reasons of the AI calls |
| [archive-history](2026-11-06/archive-history/README.md) | Answer about archive history |
| [throughput](2026-11-06/throughput/README.md) | Hourly throughput strip under the digest |
