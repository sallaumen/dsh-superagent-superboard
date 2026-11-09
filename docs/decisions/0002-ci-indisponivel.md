# ADR 0002 — CI unavailable: the local pipeline is the sufficient gate

- **Decision:** adopt local validation with evidence as a sufficient gate when CI is unavailable due to an external block. The current procedure is in [PIPELINES.md](../../PIPELINES.md#if-ci-cannot-run-no-token-billing-or-runner).
- **Status:** implemented.

## Problem and context

The account's runners were blocked by a billing issue (jobs fail within seconds with zero steps; annotation "payments have failed / spending limit"). Waiting for CI would block all deliveries because of an account condition outside the repository; re-triggering runs does not change the result and consumes quota.

## Alternatives

| Alternative | Benefit | Cost or risk |
|---|---|---|
| Block deliveries until CI returns | Maximum remote confidence | Deliveries stalled indefinitely |
| Skip validation when CI does not run | Speed | Regressions with no gate at all |
| Local gate with evidence + later re-verification (chosen) | Continuous delivery with a real gate | External verification is deferred |

## Choice and consequence

The gate remains mandatory, but its remote execution can be deferred by an
account block. [PIPELINES.md](../../PIPELINES.md#if-ci-cannot-run-no-token-billing-or-runner)
keeps the diagnosis and the procedure; AGENTS.md, CONTRIBUTING.md and the PR
template point to it. The reusable library keeps the general principle in the
[common contract](https://github.com/sallaumen/elixir-agent-kit/blob/v0.8.0/priv/library/CONTRACT.md#validate-the-changed-risk).

## Rollout and review

PRs #19 (manual dispatch and cancellation of obsolete runs), #37 (rule), #39 (template), #42 (common contract), #44 (CONTRIBUTING). Reconsider when the account has stable runners: the rule still applies to any equivalent block, not just billing.
