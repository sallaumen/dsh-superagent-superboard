---
name: accessibility
description: "Use when controls, forms, dialogs or asynchronous changes may exclude keyboard or assistive-technology users."
---

# Accessibility

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when controls, forms, dialogs or asynchronous changes may exclude keyboard or assistive-technology users.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Define the flow and applicable accessibility criteria before testing. Inspect semantic structure, accessible names, labels, focus order and keyboard operation.

2. Exercise dialogs, error messages, live updates and loading states. Check contrast, zoom, text wrapping and target sizes in the actual presentation.

3. Use automated tools to find candidates, then verify behavior manually. Prefer native semantics and repair the underlying interaction rather than adding misleading ARIA.

4. Document the tested scope, confirmed barriers and remaining limits. A limited sample or scanner result does not establish whole-product WCAG compliance.

## Completion

Concrete barriers fixed or reported with reproducible evidence and clearly bounded coverage.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
