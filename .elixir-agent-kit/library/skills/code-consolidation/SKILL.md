---
name: code-consolidation
description: "Use when unfinished features, abandoned paths or competing implementations make a codebase ambiguous."
---

# Code Consolidation

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when unfinished features, abandoned paths or competing implementations make a codebase ambiguous.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Inventory candidate paths and collect evidence of runtime use, tests, entry points and product intent. Classify each as useful and incomplete, obsolete, duplicated or uncertain.

2. Choose a destination for each candidate: finish, merge into a canonical implementation, remove with evidence, or defer with a specific question. Age and apparent inactivity are not proof of abandonment.

3. Trace dynamic references, jobs and stored data before removal. Preserve useful behavior and historical records. Avoid unrelated formatting and broad rewrites.

4. Complete one bounded cleanup and validate the surviving path, including a relevant failure case. State which uncertainty remains instead of describing the whole codebase as clean.

## Completion

A recorded disposition for the selected candidates and a verified canonical path. Test duplication is handled by test-consolidation.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
