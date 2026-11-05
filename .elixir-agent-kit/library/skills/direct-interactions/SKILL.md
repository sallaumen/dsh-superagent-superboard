---
name: direct-interactions
description: "Use when a simple selection or adjustment requires excessive forms and disconnected controls."
---

# Direct Interactions

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when a simple selection or adjustment requires excessive forms and disconnected controls.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Identify the user's decision and the business rules behind it. Consider whether a direct representation such as selection, rating, ordering or inline editing improves comprehension.

2. Keep labels, keyboard operation, focus, screen-reader semantics and non-pointer alternatives available. Do not hide validation or destructive consequences behind a gesture.

3. Define pending, success, failure and undo behavior where applicable. Optimistic UI must reconcile with persistence and recover accurately on failure.

4. Test a real completion path and a rejected or failed update. Prefer existing controls when a novel interaction has no demonstrated benefit.

## Completion

A simpler interaction with equivalent rules, accessibility and reliable persistence.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
