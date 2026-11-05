---
name: pipeline-design
description: "Use when validation pipelines lack clear ownership, local/CI parity or predictable command effects."
---

# Pipeline Design

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when validation pipelines lack clear ownership, local/CI parity or predictable command effects.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Inventory the existing checks, commands, environments and side effects. Identify which checks protect backend, frontend, library integrity and release assembly.

2. Define a canonical command for each concern and keep local execution equivalent to CI. Distinguish source checks from commands that format, seed, reset data or publish artifacts.

3. Document prerequisites, outputs and failure semantics. Keep release validation explicit when it is more effectful than a normal change gate.

4. Test command contracts and representative execution. If remote CI cannot run, follow the consuming project's documented fallback and report the missing remote evidence; do not silently turn a failed check green.

## Completion

A reproducible pipeline map with working commands, clear effects and no duplicated normative instructions.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
