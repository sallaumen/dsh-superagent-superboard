---
name: layout-density
description: "Use when spacing, alignment or information density makes a screen hard to scan or use."
---

# Layout Density

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when spacing, alignment or information density makes a screen hard to scan or use.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Identify the task, reading order and the information that should be visible together. Measure the actual layout at the widths users work with.

2. Correct misalignment, disproportionate whitespace, stretched actions and unnecessary containers using the existing spacing system. Group related content without flattening hierarchy.

3. Keep long labels, empty states and real data volumes in the layout. Do not reduce text size or touch targets simply to fit more content.

4. Check small and wide viewports, keyboard focus and overflow after the change. Keep domain rules and data semantics unchanged.

## Completion

A balanced layout supported by before/after evidence and usable content at representative sizes.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
