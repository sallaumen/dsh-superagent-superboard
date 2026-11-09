# Agent board audit — 2026-11-05

> **Historical record — November 5, 2026.** Counts, captures and states describe
> the revisions identified in this document, not the current product.
> See the [audit index and sequence](05-merge-review.md).

Original baseline `52113d4`; delivered in four chained PRs.
The [review for integration](05-merge-review.md) records the updated gates,
the conflict resolution and the compatibility with later changes on main.
Interactions with real data were read-only. Audit via headless WebKit,
1366×768 and 3440×1440 in light/dark; 375×812 additional.

| Part | Reason | Report with findings and captures | Local gate |
|---|---|---|---|
| #154 | Theme, tokens, contrast and focus | [01-theme](01-theme.md) | 151 Elixir tests + assets + library |
| #158 | Density, titles, Activity and responsiveness | [02-layout](02-layout.md) | 151 Elixir tests + assets + library |
| #161 | Health, reconnection and truthful counts | [03-health](03-health.md) | 154 Elixir tests + assets + library |
| #164 | Success/error, conversation context, AI and voice | [04-actions](04-actions.md) | 158 Elixir tests + assets + library |

All passed `scripts/ci-local.sh all`: `mix gate`, `scripts/check_assets.sh`,
`mix assets.build`, assets.deploy, validator and 20 library tests.
CI blocked by billing as reported. Rerun workflow_dispatch after release; there was
no need to wait for or re-trigger CI.

Before: [desktop](baseline-light-1366.png), [ultrawide](baseline-light-3440.png),
[mobile](baseline-mobile-ai.png). After: [light desktop](final-light-1366.png),
[dark desktop](final-dark-1366.png), [ultrawide](final-dark-3440.png).

The [final matrix](04-actions.md#final-coverage-matrix) distinguishes real interaction,
fixtures, tests and limits (real audio/microphone, screen reader and mutating operations).
The HTTP 404 from the local sync remains an external access problem; the signalling was
fixed. Pre-existing server from another checkout on 4002 preserved, audit on
4003 and fixtures on 4004/localhost:4005. Own sessions closed; zero `fixture` repositories
persisted after the rollback in the test database.

Later review: [read-only voice commands](voice-read-commands/README.md)
records paired captures and the browser flow of PR #223.
