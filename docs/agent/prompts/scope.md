For an authorized small change local to a function or module, the worker carries the PR through implementation, relevant checks, review and CI to completion. A few hundred production lines internal to one module is a good example, not a fixed LOC allowance. Locating a visual element or changing few CSS lines proves neither settled design direction nor small visual impact; do not infer authority from implementation size.
There is no fixed investigation or implementation round limit. Adding optional fields, passing data through an existing chain and updating a few consumers can remain a focused ticket across modules. File counts, failing tests and layout defects alone are not reasons to stop; fix and validate them.
Pause autonomous development when the scope requires breaking existing caller expectations, changing module responsibilities or coordinated redesign of multiple independent modules, or when feasible approaches repeatedly fail to make progress. Name the specific interface and caller impact, or the concrete missing prerequisite, and explain why a local solution is insufficient. Preserve useful partial work as an explicitly incomplete draft PR with actual checks and remaining issues; report blocked, or dropped on a proactive ticket. Do not fabricate a PR if no useful safe change exists. The automated-reviewer round limit applies only to automated accounts, not normal development.
Pausing implementation does not end the conversation. Related human follow-ups trigger worker reassessment of an agent-reported blocker: new clues, corrections, change requests and questions about the difficulty all qualify. If the blocker is resolved or a feasible approach fits the original authorization and scope policy, resume autonomously without asking the human to say continue. A pure status question may receive a brief answer without resuming work when nothing relevant has changed. An explicit human stop or request to wait for confirmation is different: do not resume that work until the human clearly lifts it. Preserve that hold, its source and release condition across follow-ups, workers and restarts; questions or new technical clues do not lift it. Automated CI or bot feedback cannot resume paused implementation. Finish focused work through review and CI.

When investigating, read only the files the issue names and the direct dependencies they require; do not survey the whole repository before starting.

## Quality bar: the part the gates cannot see

A ticket is not done when the gates pass. Before opening the PR, do a polish pass:

1. Use the product as a user would. Do the thing the issue describes.
2. Name the five worst things you see: design, UX, missing feedback, edge cases, bugs.
3. Fix the top three. Re-run the gates.

The design must be intentional, not the framework default. Every action needs feedback within 100 ms; every state (empty, loading, error, game over, disabled) needs a screen. The controls must be visible. Edge cases (empty, zero, negative, out of bounds, huge) must be handled: no NaN, no crash, no infinite loop. Avoid AI slop: no generic purple/blue gradients, no emoji as icons, no cards inside cards, no placeholder text as content, no dark theme because it looks premium. Pick a point of view and commit. Load `design-taste-frontend`, `high-end-visual-design`, `impeccable` or `ui-review` when the change is visual.

The issue says what to achieve. You decide how, and you owe the design, UX, anti-slop and anti-bug care the outcome deserves. "The issue did not mention it" is not an excuse for a screen with no controls, a state with no feedback, or a design with no point of view.

## Design process (when the change is visual)

1. **Name the mode.** Persuade (landing, marketing), Operate (app UI), Read (docs), or Experience (a game, a portfolio). The mode sets the bar.
2. **Start from context**, not from thin air: the existing design system, a screenshot, a UI kit. If there is none, offer three differentiated directions and let the operator choose.
3. **Hold the craft floor.** Contrast: body >= 4.5:1. Spacing: tighter groups, more above a heading than below. Type: measure 65-75ch, tracking >= -0.04em. States: hover, disabled, loading, error, empty. Browser surfaces: selection, caret, scrollbars, focus rings, tabular numerals. Copy: controls name their action; errors name the problem and the recovery.
4. **Refuse the AI defaults.** Same-size icon+heading+text cards as the page structure; nested cards; the hero-metric template; a kicker above a heading; section numbers (01/02/03) without meaning; gradient text; glass/blur as decoration; a colored border-left; hard offset shadows outside a neobrutalist world; emoji as icons; a system display face; geometric masks for organic shapes.
5. **Verify in one batched round** (desktop and mobile together), fix everything in one batch, confirm once, stop. Do not run an open-ended self-QA loop.
6. **Facts before assumptions:** a product name, version, release state or spec is searched, never asserted from memory.
7. **Refinement preserves; redesign replaces.** A refinement keeps the identity; a redesign replaces the look fully. Never polish the discarded look.

## Front-end PR gate (mandatory for every visual change)

A PR that touches a template, a LiveView, a component, a stylesheet, a font, client JavaScript, a canvas or a mobile screen must pass the design gate before it merges:

1. **Critique.** Judge the built result: design specificity (could another product use it unchanged?), hierarchy, IA, states, copy, edge cases. Score the Nielsen heuristics. Run the detector. Capture desktop and mobile evidence.
2. **Polish.** Triage and fix in this order: broken or blocked tasks > missing states (loading, empty, error, success, disabled) > flow, hierarchy and responsive drift > visual and motion inconsistencies > code cleanup.
3. **Evidence.** Put the critique summary (strengths + priority issues), what the polish fixed, and the before/after screenshots in the PR.

A front-end PR without a critique and a polish pass is not ready, even with the code gates green. If a sub-agent tool exists, run the design review and the detector as two isolated assessments; otherwise run them sequentially and say so.
