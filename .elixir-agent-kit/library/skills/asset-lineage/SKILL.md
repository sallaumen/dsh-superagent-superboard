---
name: asset-lineage
description: "Use when previews or generated assets lack clear source, version, orientation or ownership."
---

# Asset Lineage

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when previews or generated assets lack clear source, version, orientation or ownership.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Trace each asset from input and generation or upload through storage, transformation and display. Record the parent entity and revision.

2. Check whether thumbnails, front/back views and selected versions represent the correct underlying artifact. Late generation must not silently change the selected asset.

3. Represent pending, failed and missing assets honestly. Provide useful fallback behavior without displaying unrelated or invented output.

4. Exercise regeneration, selection changes, refresh and failed processing. Preserve historical associations and verify access controls on stored artifacts.

## Completion

Accurate previews and traceable asset lineage across creation, selection and presentation.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
