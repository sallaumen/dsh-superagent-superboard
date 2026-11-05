---
name: code-review
description: "Use when reviewing a bounded diff or pull request for actionable defects and regressions."
---

# Code Review

Default mode: **review**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when reviewing a bounded diff or pull request for actionable defects and regressions.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Read the mandate, base/head and project contracts before examining the diff. Follow changed behavior through relevant callers and boundaries.

2. Prioritize correctness, security, data integrity, compatibility and missing regression coverage. Explain each finding with a concrete trigger, consequence and precise location.

3. Separate demonstrated defects from hypotheses and stylistic preferences. Check whether existing tests actually exercise the risky path.

4. Return actionable findings ordered by severity, or state that no actionable defect was found within the reviewed scope. Do not edit, post comments, approve, merge or run effectful operations unless separately authorized.

## Completion

An independent read-only assessment with evidence and coverage limits. No findings is not proof that all behavior is correct.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
