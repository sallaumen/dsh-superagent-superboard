---
name: test-strategy
description: "Use when a passing suite misses important bugs or the required regression coverage is unclear."
---

# Test Strategy

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when a passing suite misses important bugs or the required regression coverage is unclear.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. List the behaviors and boundaries that can fail in the selected change. Rank risks by consequence and likelihood using actual incidents and code paths.

2. Choose the smallest test that crosses the boundary responsible for each risk. Use integration tests when isolated mocks would hide contract mismatches.

3. Control time, concurrency, persistence and external responses so failures are reproducible. Include an adverse condition when that is where the risk lives.

4. Prove a regression test reaches the intended behavior, preferably by observing it fail before the fix. Do not pursue coverage percentage through redundant assertions.

## Completion

A justified test plan and meaningful coverage for the selected risks, with remaining gaps stated.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
