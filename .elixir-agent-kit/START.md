# Elixir Agent Kit 0.1.1

Read the [shared contract](library/CONTRACT.md) before using a workflow.
Project instructions and the user's authorized scope govern the work.
Choose the smallest relevant workflow below; do not load the whole catalog.
Use the [Elixir context](library/ELIXIR.md) only for technologies present in this project.
Skills are guidance, not permission to publish, merge, deploy or call paid models.
For a handoff, use the [handoff template](library/HANDOFF.md).

## Enabled workflows

- [delivery-coordination](library/skills/delivery-coordination/SKILL.md): Use when consolidating a product or dividing an authorized change into reviewable deliveries.
- [architecture-review](library/skills/architecture-review/SKILL.md): Use when changes cross many modules, rules repeat, dependencies cycle or domain ownership is unclear.
- [abstraction-layers](library/skills/abstraction-layers/SKILL.md): Use when functions mix business decisions, low-level details and effects at incompatible levels.
- [module-design](library/skills/module-design/SKILL.md): Use when module names, locations or public APIs obscure responsibilities that are already understood.
- [code-consolidation](library/skills/code-consolidation/SKILL.md): Use when unfinished features, abandoned paths or competing implementations make a codebase ambiguous.
- [version-lineage](library/skills/version-lineage/SKILL.md): Use when revisions, previews, selections or generated artifacts are associated with the wrong version.
- [data-contracts](library/skills/data-contracts/SKILL.md): Use when layers disagree about data, rules are duplicated or a write leaves records inconsistent.
- [ui-identity](library/skills/ui-identity/SKILL.md): Use when a working interface lacks product-specific hierarchy, identity or visual coherence.
- [layout-density](library/skills/layout-density/SKILL.md): Use when spacing, alignment or information density makes a screen hard to scan or use.
- [navigation-ux](library/skills/navigation-ux/SKILL.md): Use when users lose context or need unnecessary steps to complete a multi-screen task.
- [responsive-mobile](library/skills/responsive-mobile/SKILL.md): Use when mobile navigation, browser history or layouts fail across phone and wide-screen sizes.
- [direct-interactions](library/skills/direct-interactions/SKILL.md): Use when a simple selection or adjustment requires excessive forms and disconnected controls.
- [accessibility](library/skills/accessibility/SKILL.md): Use when controls, forms, dialogs or asynchronous changes may exclude keyboard or assistive-technology users.
- [design-system](library/skills/design-system/SKILL.md): Use when teams repeat interface mistakes or create incompatible component and token variations.
- [performance](library/skills/performance/SKILL.md): Use when measured latency, freezes, excessive work or rendering cost affects a real workflow.
- [async-state](library/skills/async-state/SKILL.md): Use when progress stalls, success appears too early or stale asynchronous results overwrite current state.
- [ai-orchestration](library/skills/ai-orchestration/SKILL.md): Use when agent jobs, queues, workers and model capacity are conflated or incorrectly accounted for.
- [notifications](library/skills/notifications/SKILL.md): Use when bots or notifications fail, repeat or produce unexplained message volume.
- [integration-setup](library/skills/integration-setup/SKILL.md): Use when an integration looks configured but required steps or operational readiness remain unclear.
- [commercial-eligibility](library/skills/commercial-eligibility/SKILL.md): Use when an offering is presented without evidence that its exact variant and destination are supported.
- [asset-lineage](library/skills/asset-lineage/SKILL.md): Use when previews or generated assets lack clear source, version, orientation or ownership.
- [metrics-costs](library/skills/metrics-costs/SKILL.md): Use when totals, model costs or operational metrics have unclear scope, origin or meaning.
- [operational-alerts](library/skills/operational-alerts/SKILL.md): Use when alerts repeat, historical incidents look current or acknowledging an alert appears to resolve it.
- [simulation-isolation](library/skills/simulation-isolation/SKILL.md): Use when simulation, training or demo flows share code and data paths with real operations.
- [test-consolidation](library/skills/test-consolidation/SKILL.md): Use when duplicated tests slow maintenance without protecting distinct failure modes.
- [test-strategy](library/skills/test-strategy/SKILL.md): Use when a passing suite misses important bugs or the required regression coverage is unclear.
- [code-review](library/skills/code-review/SKILL.md): Use when reviewing a bounded diff or pull request for actionable defects and regressions.
- [debugging](library/skills/debugging/SKILL.md): Use when a wrong result, exception or intermittent failure has no demonstrated root cause.
- [security-boundaries](library/skills/security-boundaries/SKILL.md): Use when untrusted input, credentials, permissions or tenant boundaries may permit unintended access.
- [migration-compatibility](library/skills/migration-compatibility/SKILL.md): Use when stored schemas, identifiers, jobs or public payloads must survive a version change.
- [pipeline-design](library/skills/pipeline-design/SKILL.md): Use when validation pipelines lack clear ownership, local/CI parity or predictable command effects.
- [build-dependencies](library/skills/build-dependencies/SKILL.md): Use when dependencies, builds or CI fail or behave differently across environments.
- [delivery-validation](library/skills/delivery-validation/SKILL.md): Use when checking whether an integrated change actually satisfies its acceptance criteria.
