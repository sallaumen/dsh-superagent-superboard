---
name: operational-alerts
description: "Use when alerts repeat, historical incidents look current or acknowledging an alert appears to resolve it."
---

# Operational Alerts

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when alerts repeat, historical incidents look current or acknowledging an alert appears to resolve it.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Identify the underlying condition, its scope and the signal that proves recovery. Separate a current problem from individual notifications about it.

2. Model detection, acknowledgement, escalation and resolution as distinct transitions. A person viewing an alert is not evidence that the system recovered.

3. Define deduplication, recurrence and stale-data behavior. Preserve history while keeping current severity tied to observed state.

4. Test repeated detection, acknowledgement, actual recovery and a new recurrence. Use notifications for transport-specific failures.

## Completion

A coherent incident lifecycle with truthful current status and useful historical records.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
