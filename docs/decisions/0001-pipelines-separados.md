# ADR 0001 — Separate pipelines by technology, with a mixed release path

- **Decision:** replace the single CI job with separate pipelines — backend, frontend and capability library — plus a mixed release job. The current distribution of checks is in [PIPELINES.md](../../PIPELINES.md).
- **Status:** implemented.

## Problem and context

CI was a single job (`gates`) that mixed formatting, credo and tests without covering the frontend (no asset build was exercised) or the capability library. A failure did not say which side broke; changing CSS reprocessed the backend; and the developer had no local command equivalent to CI.

## Alternatives

| Alternative | Benefit | Cost or risk |
|---|---|---|
| Keep a single job | Simplicity | Failure not attributable; frontend/library uncovered; local × CI diverge |
| Separate pipelines + mixed release (chosen) | Attributable failure, independent cycles, local×CI parity | More jobs to maintain |
| Mixed pipeline for everything | Fewer files | Loses failure attribution; higher context cost |

## Choice and consequence

The pipelines let failures be attributed to the corresponding technology and let
specific checks run during iteration. The release exercises the integration between
assets and the production application. The operational matrix, the environments and the relationship
between local commands and jobs are kept in [PIPELINES.md](../../PIPELINES.md).

## Rollout and review

PRs #13, #14, #15, #16, #17, #18, #21, #38, #40. Reconsider if a new stack makes the separation artificial (e.g. E2E tests that require both sides — they belong in the mixed job, not the separate ones).
