---
name: test-consolidation
description: "Use when duplicated tests slow maintenance without protecting distinct failure modes."
---

# Test Consolidation

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when duplicated tests slow maintenance without protecting distinct failure modes.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Map the behavior and risk each candidate test protects. Similar setup or assertions do not by themselves prove redundancy.

2. Identify overlap at unit, boundary and integration levels. Retain tests that detect different failure paths, concurrency conditions or contract violations.

3. Remove or combine one supported duplicate at a time and preserve readable fixtures. Avoid replacing meaningful behavior tests with implementation-shaped assertions.

4. Run the affected tests and the required project gate. Record any lost coverage intentionally and explain why remaining tests still detect the relevant regression.

## Completion

A leaner suite with preserved risk coverage. Use test-strategy to discover missing protection.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
