---
name: simulation-isolation
description: "Use when simulation, training or demo flows share code and data paths with real operations."
---

# Simulation Isolation

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when simulation, training or demo flows share code and data paths with real operations.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Map environment identity and the boundaries around data, credentials, jobs and external effects. Confirm the mode at the effect boundary, not only in a visual label.

2. Define what is simulated and what remains real. Keep scenarios reproducible and distinguish training outcomes from production metrics.

3. Trace reset, replay and cleanup operations to their exact storage scope. Preserve unrelated history and require explicit authority for destructive operations.

4. Test that a simulated path cannot invoke the production effect and that production does not consume simulated records. Include queued work and stale configuration.

## Completion

Demonstrated isolation and coherent scenario lifecycle, with any mixed real/simulated effects explicitly documented.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
