---
name: metrics-costs
description: "Use when totals, model costs or operational metrics have unclear scope, origin or meaning."
---

# Metrics Costs

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when totals, model costs or operational metrics have unclear scope, origin or meaning.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Define each metric's unit, population, time window, source and aggregation rule. Trace displayed totals back to underlying events or provider records.

2. Distinguish measured, estimated, unavailable and zero. Keep model usage, provider billing and application operations separate unless their relationship is explicitly defined.

3. Check duplicates, currency or unit conversion, partial periods and delayed records. Reconcile a small known sample before changing a whole dashboard.

4. Expose limitations and last-update context where they affect interpretation. Never manufacture precise costs from incomplete token or pricing information.

## Completion

Reproducible metrics with clear provenance and honest handling of missing or estimated data.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
