---
name: abstraction-layers
description: "Use when functions mix business decisions, low-level details and effects at incompatible levels."
---

# Abstraction Layers

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when functions mix business decisions, low-level details and effects at incompatible levels.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Choose one real operation and read its public entry point and immediate collaborators. Describe the vocabulary a reader must understand at each level.

2. Identify business decisions obscured by transport, persistence, parsing or UI mechanics. Separate actions, calculations and data when this makes effects and dependencies visible.

3. Extract cohesive operations with names from the domain. Keep small calculations as functions; a new abstraction does not imply a new process, context or framework.

4. Compare the before and after call paths. The caller should express a coherent operation without forcing the reader to chase a chain of trivial wrappers. Test observable behavior and effect boundaries.

## Completion

A clearer operation with justified abstraction boundaries and preserved behavior. Whole-system domain ownership belongs to architecture-review.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
