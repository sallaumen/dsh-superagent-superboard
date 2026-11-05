---
name: ui-identity
description: "Use when a working interface lacks product-specific hierarchy, identity or visual coherence."
---

# Ui Identity

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when a working interface lacks product-specific hierarchy, identity or visual coherence.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Inspect the running interface and the existing design direction before editing. Identify the primary user task, information hierarchy and useful local conventions.

2. Use the product vocabulary, typography, spacing and component system to distinguish important actions and content. Replace generic visual treatments only when their consequences are clear.

3. Preserve functional states, accessibility and responsive behavior. Avoid invented metrics, decorative controls, unverifiable claims and placeholder interactions.

4. Validate the changed flow in a browser at relevant widths. Record what was actually observed; screenshots alone do not establish interaction correctness.

## Completion

A coherent, task-oriented interface with working states and browser evidence. For a narrow spacing problem use layout-density; for an end-to-end journey use navigation-ux.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
