---
name: security-boundaries
description: "Use when untrusted input, credentials, permissions or tenant boundaries may permit unintended access."
---

# Security Boundaries

Default mode: **analyze-and-fix**. Read the [shared contract](../../CONTRACT.md) before applying this workflow. The user's explicit scope overrides the default mode.

## When to use

Use when untrusted input, credentials, permissions or tenant boundaries may permit unintended access.

## Useful inputs

The requested outcome, affected flow or diff, project instructions, relevant evidence and acceptance criteria. Discover available context before asking for missing information.

## Workflow

1. Map the actor, resource, trust boundary and intended authorization rule for the selected operation. Trace inputs through parsing, storage and effects.

2. Check authorization at the actual read/write boundary, tenant scoping, secret handling, path traversal and unsafe interpretation of external content where relevant.

3. Use controlled fixtures and local or explicitly authorized systems. Do not perform offensive tests against third parties or extract real sensitive records to prove a finding.

4. Fix a demonstrated issue and test the allowed and denied paths. Describe the scope and remaining uncertainty without claiming a comprehensive security certification.

## Completion

Concrete boundary findings or fixes with evidence of both legitimate and rejected operations.

Use the [Elixir context](../../ELIXIR.md) only for technology present in the project. Record a useful [handoff](../../HANDOFF.md) when another person or agent will continue the work.
