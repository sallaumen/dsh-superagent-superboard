# 1 — Component regions and stable card identity

Baseline: main `be2c29c`, pulled before work. Preview: http://127.0.0.1:4002,
Postgres 5434. `mix setup` completed. WebKit headless, read-only interactions.

| Severity | Region | Evidence | Correction |
|---|---|---|---|
| P2 | Composition | Previous BoardLive: 835 lines; now 398 | Header, Column, Card, Activity, Conversation, Intake, AI and CreateTask each have their own LiveComponent. Formatting is in Presentation; domain calls and events stay in BoardLive. |
| P2 | Real-time cards | Original repeated cards lacked DOM IDs; `board_components/column.ex` now keys each task/pull by database ID | Stable component and DOM identity; test moves a card between columns and repeats broadcast three times, asserting one card and an intact conversation. |

[Before](01-before.png) / [after](01-after.png): the extraction preserves visual
layout. Native connection cycling showed reconnecting then live; the unsent
input value and focus survived. No real tasks or messages were submitted.
Baseline full page and disconnected screenshots are included alongside this file.

`scripts/ci-local.sh all` exited 0: 169 Elixir tests, Credo/compile/format/deps,
Sobelow, check_assets.sh, assets.build/deploy, library validator and 20 tests.
[Full log](01-gate.log). Local gate substitutes billing-blocked CI per PIPELINES.md.
The test fixture database is separate from real data. No domain files changed.
