---
name: commercial-eligibility
description: "Use when an offering is presented without evidence that its exact variant and destination are supported."
---

# Commercial Eligibility

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when an offering is presented without evidence that its exact variant and destination are supported.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Identify the exact product, variant, supplier, market and destination combination. Locate the authoritative provider data and record when it was checked.

2. Separate supported, unsupported, unknown and stale eligibility. A general provider capability does not prove support for a specific combination.

3. Trace eligibility through catalog, selection, pricing and fulfillment. Prevent presentation layers from replacing unknown data with an optimistic default.

4. Test unsupported and expired information alongside a supported combination. Preserve the evidence and reason for a block; avoid guarantees beyond the provider's confirmed contract.

## Completion

Eligibility decisions backed by scoped, dated evidence and consistently enforced across the purchase or production flow.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
