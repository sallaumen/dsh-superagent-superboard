---
name: responsive-mobile
description: "Use when mobile navigation, browser history or layouts fail across phone and wide-screen sizes."
---

# Responsive Mobile

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when mobile navigation, browser history or layouts fail across phone and wide-screen sizes.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Separate navigation defects from layout defects. Reproduce back-button behavior, modal history, deep links and refresh on the relevant flow.

2. Inspect phone, notebook and wide-screen layouts with meaningful content. Check overflow, sticky elements, virtual keyboards and reachable actions.

3. Preserve navigation state and remove phantom history entries only after understanding how routes and overlays are modeled. Adapt composition using existing breakpoints and design conventions.

4. Verify mouse, touch-equivalent and keyboard interactions. State whether evidence comes from emulation or a physical device; do not claim device coverage from a resized screenshot.

## Completion

Correct navigation and usable layouts across a declared viewport/device matrix, with unsupported cases identified.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
