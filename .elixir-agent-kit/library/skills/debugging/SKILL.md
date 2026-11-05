---
name: debugging
description: "Use when a wrong result, exception or intermittent failure has no demonstrated root cause."
---

# Debugging

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when a wrong result, exception or intermittent failure has no demonstrated root cause.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Capture the symptom, expected behavior and conditions needed to reproduce it. Establish whether the failure is current and distinguish it from unrelated baseline problems.

2. Form a small set of competing hypotheses. Use logs, traces or targeted experiments that discriminate among them, avoiding broad changes that hide the cause.

3. Trace the failing value or transition to its owner. Fix the responsible boundary and preserve the intended error behavior.

4. Verify the original reproduction and add a meaningful regression test when justified. Record untested intermittent conditions and the evidence supporting the root cause.

## Completion

A reproduced failure, supported causal explanation and verified correction, or a precise blocker and next diagnostic step.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
