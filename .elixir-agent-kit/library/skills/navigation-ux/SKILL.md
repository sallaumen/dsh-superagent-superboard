---
name: navigation-ux
description: "Use when users lose context or need unnecessary steps to complete a multi-screen task."
---

# Navigation Ux

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when users lose context or need unnecessary steps to complete a multi-screen task.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Walk a complete user journey, including entry, intermediate decisions, cancellation, completion and return. Use actual application state rather than a screenshot-only interpretation.

2. Locate lost filters, confusing labels, redundant forms, unexpected navigation and missing recovery. Explain how each problem affects task completion.

3. Simplify the flow while retaining business constraints and meaningful confirmations. Preserve selected entities and unsaved work according to the product rules.

4. Verify browser back/forward, direct links, refresh and error recovery where relevant. Confirm the user can tell what happened and what to do next.

## Completion

A complete, validated journey with fewer avoidable steps and preserved context. A single visual composition issue belongs to ui-identity or layout-density.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
