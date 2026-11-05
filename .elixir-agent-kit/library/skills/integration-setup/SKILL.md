---
name: integration-setup
description: "Use when an integration looks configured but required steps or operational readiness remain unclear."
---

# Integration Setup

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when an integration looks configured but required steps or operational readiness remain unclear.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Map prerequisites, credentials, permissions, provider resources and the final operation the user wants to perform. Confirm provider requirements from primary documentation for the actual version/account context.

2. Separate saved configuration, authenticated access and proven readiness. Show missing or unknown steps without fabricating a successful status.

3. Make setup resumable and keep secrets in the project's established mechanism. Links should point to verified destinations and explain the next action.

4. Test incomplete setup, invalid access and a controlled ready-state operation. Apply commercial-eligibility when readiness depends on a specific offering, market or destination.

## Completion

A clear, resumable setup flow with evidence for each readiness claim.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
