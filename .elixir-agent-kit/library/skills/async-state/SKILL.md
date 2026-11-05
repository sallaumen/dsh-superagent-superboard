---
name: async-state
description: "Use when progress stalls, success appears too early or stale asynchronous results overwrite current state."
---

# Async State

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when progress stalls, success appears too early or stale asynchronous results overwrite current state.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Trace the command, queued or running work, persisted result and user-visible state. Identify which component owns each transition.

2. Model pending, running, completed, failed, canceled and unknown only as supported by actual evidence. A submitted request is not a completed operation.

3. Correlate results with their request, entity and version. Prevent late responses from replacing newer selections; define reconnect, refresh and subscription cleanup behavior.

4. Exercise out-of-order completion, partial failure and recovery. Keep the last valid state when a network failure prevents a fresh read.

## Completion

A truthful state lifecycle that survives refresh, reconnection and stale responses without invented success.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
