---
name: performance
description: "Use when measured latency, freezes, excessive work or rendering cost affects a real workflow."
---

# Performance

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when measured latency, freezes, excessive work or rendering cost affects a real workflow.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Reproduce the slow operation and record a baseline under stated data, device and workload conditions. Choose a measurement that reflects user impact.

2. Trace expensive database queries, repeated work, blocking calls, rendering and resource lifecycles. Use a profiler or targeted instrumentation before attributing the issue to a framework.

3. Change one supported cause and compare under equivalent conditions. Preserve correctness, cancellation, cleanup and observability.

4. Report improvement with its measurement limits. An asynchronous state bug belongs to async-state even if it appears as a spinner.

## Completion

A measured diagnosis and improvement, or a narrowed hypothesis with the next discriminating measurement.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
