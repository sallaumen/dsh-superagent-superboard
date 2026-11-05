---
name: notifications
description: "Use when bots or notifications fail, repeat or produce unexplained message volume."
---

# Notifications

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when bots or notifications fail, repeat or produce unexplained message volume.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Trace event creation, routing, delivery attempts and provider responses. Separate configured, connected and successfully delivered states.

2. Investigate duplicate pollers, repeated subscriptions, stale credentials, conflicting endpoints and provider limits using evidence. Do not infer a provider ban from a missing response.

3. Define deduplication, retry and ordering behavior for the actual delivery semantics. Avoid contacting real recipients during tests unless explicitly authorized.

4. Verify one successful and one failed delivery with controlled fixtures. Keep secrets out of logs and expose a useful diagnostic reason.

## Completion

A grounded transport diagnosis and reliable delivery behavior. The lifecycle of the underlying operational problem belongs to operational-alerts.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
