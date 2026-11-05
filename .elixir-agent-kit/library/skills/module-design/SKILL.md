---
name: module-design
description: "Use when module names, locations or public APIs obscure responsibilities that are already understood."
---

# Module Design

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when module names, locations or public APIs obscure responsibilities that are already understood.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Map the selected modules, their callers and the project naming conventions. State the responsibility each public API is meant to expose.

2. Find misleading names, helpers placed under the wrong owner and public functions without a genuine consumer. Choose names that describe behavior and domain meaning.

3. Before moving or renaming, search aliases, callbacks, configuration, supervision children, dynamic dispatch, serialized module names and persisted jobs. Direct call search alone is insufficient.

4. Make the smallest coherent move and update consumers together. Preserve compatibility for persisted identifiers or publish a migration path. Do not expose private functions solely to make tests easier.

## Completion

An understandable module/API arrangement with consumers and compatibility checked. If ownership is not established, use architecture-review first.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
