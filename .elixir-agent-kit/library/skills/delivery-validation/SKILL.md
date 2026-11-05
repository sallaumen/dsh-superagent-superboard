---
name: delivery-validation
description: "Use when checking whether an integrated change actually satisfies its acceptance criteria."
---

# Delivery Validation

Default mode: **analyze**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when checking whether an integrated change actually satisfies its acceptance criteria.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Read the requested outcome, scope and acceptance criteria. Identify the exact revision and changes being validated.

2. Choose evidence proportional to the changed risk: tests, integration exercises, browser flows or artifact inspection. Check at least the critical completion path and relevant failure/recovery behavior.

3. Compare the integrated result with the mandate, not only a worker's report. Separate inspected, simulated, executed, published and unverified claims.

4. Report passed, failed, blocked and deferred criteria with reproducible evidence. Do not silently switch from validation to repair, publish, merge or deploy without the necessary authority.

## Completion

A precise acceptance assessment and handoff. A passing test suite alone does not prove every requested behavior was delivered.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
