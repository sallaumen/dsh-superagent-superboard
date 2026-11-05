---
name: design-system
description: "Use when teams repeat interface mistakes or create incompatible component and token variations."
---

# Design System

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when teams repeat interface mistakes or create incompatible component and token variations.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Inventory the components, tokens and documentation actually used by the project. Distinguish intentional exceptions from accidental divergence.

2. Choose a canonical source for each rule and component. Consolidate repeated patterns without forcing distinct product needs into one abstraction.

3. Document behavior, states, accessibility and responsive expectations alongside visual values. Make project instructions point to canonical guidance rather than duplicating it.

4. Validate representative consumers after changing a shared component. Provide examples that exist and name unresolved migration work.

## Completion

A usable design system and operational guidance with tested consumers, not a document disconnected from implementation.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
