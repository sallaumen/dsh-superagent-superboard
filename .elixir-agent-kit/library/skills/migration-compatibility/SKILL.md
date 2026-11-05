---
name: migration-compatibility
description: "Use when stored schemas, identifiers, jobs or public payloads must survive a version change."
---

# Migration Compatibility

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when stored schemas, identifiers, jobs or public payloads must survive a version change.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Inventory readers, writers and persisted representations, including queued jobs and serialized module names. Determine which old and new versions may coexist.

2. Plan an expand/migrate/contract sequence when immediate replacement would break live consumers. Specify backfill, validation and recovery behavior.

3. Assess locks, data volume, duplicate processing and irreversible operations before running a migration. Planning does not authorize destructive production changes.

4. Test representative old data and mixed-version interactions. Document the supported rollback boundary and verify post-migration invariants.

## Completion

A compatible transition with evidence for historical data and a practical rollout/recovery plan.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
