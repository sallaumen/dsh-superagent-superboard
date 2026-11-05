---
name: ai-orchestration
description: "Use when agent jobs, queues, workers and model capacity are conflated or incorrectly accounted for."
---

# Ai Orchestration

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when agent jobs, queues, workers and model capacity are conflated or incorrectly accounted for.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Map requests, jobs, workers, agents and provider calls as distinct entities. Trace which execution paths actually invoke a model, including conditional calls and delegation.

2. Identify the owner of admission control, concurrency, cancellation, retries and budget checks. Queue concurrency and provider capacity are different constraints.

3. Record calls and outcomes with sufficient provenance to reconcile usage without exposing prompts or secrets unnecessarily. Avoid counting a delegated call twice.

4. Test saturation, cancellation and failure using controlled responses. Do not add retries to paid or effectful calls without an explicit policy and duplicate-effect analysis.

## Completion

An explicit execution/capacity contract and accounting aligned with observed behavior. Visual style belongs to the project design context.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
