---
name: version-lineage
description: "Use when revisions, previews, selections or generated artifacts are associated with the wrong version."
---

# Version Lineage

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when revisions, previews, selections or generated artifacts are associated with the wrong version.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Identify stable entity identity, immutable revision identity and the mutable selected or published pointer. Trace creation, selection, preview and publication separately.

2. Inspect how asynchronous results and assets record their parent revision, inputs and provenance. A late result must not silently replace a newer selection.

3. Make browsing read-only with respect to selection unless the product explicitly defines otherwise. Distinguish available, selected and published versions in both storage and presentation.

4. Exercise refresh, concurrent creation, stale completion and rollback. Preserve historical associations during a migration.

## Completion

A consistent version lifecycle with traceable artifacts and independent viewing/selection. This workflow concerns product revisions, not dependency upgrades.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
