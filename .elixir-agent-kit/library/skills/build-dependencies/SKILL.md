---
name: build-dependencies
description: "Use when dependencies, builds or CI fail or behave differently across environments."
---

# Build Dependencies

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when dependencies, builds or CI fail or behave differently across environments.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Reproduce the exact failing command with its language/runtime versions, lockfile and environment. Distinguish infrastructure unavailability from code failure.

2. Inspect compatibility requirements and dependency usage before upgrading or removing anything. Preserve reproducibility and change only the relevant dependency boundary.

3. Compare local and CI commands, caches, permissions and service prerequisites. Never disable a meaningful check or swallow a nonzero exit merely to obtain green output.

4. Verify the repaired command and required project gates. Report residual infrastructure limits and avoid incidental publishing or deployment.

## Completion

A grounded build failure diagnosis and reproducible repair. Use pipeline-design for reorganizing validation responsibilities.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
