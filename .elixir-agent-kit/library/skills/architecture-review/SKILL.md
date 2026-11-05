---
name: architecture-review
description: "Use when changes cross many modules, rules repeat, dependencies cycle or domain ownership is unclear."
---

# Architecture Review

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when changes cross many modules, rules repeat, dependencies cycle or domain ownership is unclear.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Trace representative operations from entry point to data changes and output. Include failure, repetition and recovery where they affect responsibilities. Compare documented boundaries with the code that actually runs.

2. Identify data owners, public contracts, dependency direction and effects. Support each finding with a path, symbol or observed flow and a concrete maintenance or correctness consequence.

3. Prefer a small boundary correction that improves the selected operation. Do not equate pages with domains, line counts with quality, or a folder rearrangement with architectural improvement.

4. Check callers, callbacks, configuration, serialization and persisted jobs before changing a public boundary. Validate the affected contracts and failure paths.

## Completion

An evidence-backed boundary assessment and, only when authorized, a bounded correction. Use abstraction-layers for meaning within a module and module-design for an already-understood organizational change.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
