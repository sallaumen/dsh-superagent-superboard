---
name: data-contracts
description: "Use when layers disagree about data, rules are duplicated or a write leaves records inconsistent."
---

# Data Contracts

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when layers disagree about data, rules are duplicated or a write leaves records inconsistent.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Trace a value across UI, API, domain logic, database and external services. Identify the authoritative owner for each field, invariant and state transition.

2. Compare actual types, nullable values, identifiers and error states. Do not turn unknown into zero or let presentation-layer guesses become persisted truth.

3. Move duplicated decisions to the appropriate boundary and validate inputs before effects. Use transactions for related local writes; describe external consistency and compensation explicitly.

4. Test the full affected flow, including an invalid input and a partial failure. If a schema or stored payload changes, apply the migration-compatibility workflow.

## Completion

Explicit ownership and consistent boundary behavior, supported by a representative integration test or reproducible evidence.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
