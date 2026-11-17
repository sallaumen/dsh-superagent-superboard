# From a request to reviewable issues

In **New request → Split automatically**, review **How to verify** for each
selected issue. Edit the scenario or clear it. Under **Include guides in this
issue**, choose which references the executor should see. Sending the proposal
publishes the reviewed text; retrying a partial submission reuses it.

The splitting call also receives the original wording alongside the refined spec. A condition for a diagnostic recording (such as hiding damage numbers) should not become a change to the game. The model proposes a scenario; the owner still reviews it.

Acceptance describes **what should be true**. Verification describes **how a
reviewer could tell**. Neither is a receipt. A suggested guide is optional and
cannot install tools, run commands, approve a PR or change project merge rules.

## What we learned from reviewing a crowded combat scene

The first hit animation passed behavioral checks but its effect vanished inside
the beam. A matched scene with damage numbers hidden exposed the problem; an
unharmed neighbour and a shot from the opposite side distinguished a convincing
effect from one drawn on the wrong body or side. The review also found that
repeated state deliveries must not replay a real hit. Later, a long video timed
out in CI: recapture or re-encode evidence without weakening the gate.
Apply the idea, not the game's checklist, to the next project:

| Primary method | Useful proof in a child issue |
| --- | --- |
| Motion | Replay the same scene at normal speed; show the target and an unaffected neighbour. |
| Interaction | Repeat a named user action; show the resulting state and how to recover or retry. |
| Performance | Run the same workload before and after; retain the measurement and conditions. |
| Regression | Reproduce the original failure and exercise a neighbouring case that must stay unchanged. |
| Inspection | Give a worked example or a traceable finding that answers the question. |

These are examples, not mandatory thresholds. A documentation change does not
need a video. A verification step belongs to its deliverable unless independent
review is itself requested. Real dependencies still determine execution order.

## Where guidance comes from

1. **The project's default branch.** The board reuses the existing GitHub tree
   read. It recognises motion review documents and discovers up to 32 custom
   `.agents/skills/<lowercase-id>/SKILL.md` paths (sorted). The model can suggest
   one relevant listed path per issue. The board checks the path against the
   tree, builds the link itself and offers matching project guides selected.
   Uncheck any you do not want. Project links follow the default branch.
2. **The machine that runs the board.** After the model responds, the board checks
   for known `SKILL.md` files under `~/.agents/skills` and `~/.codex/skills`.
   Motion can suggest `motion-designer` and `ui-review`; interaction, `ui-review`;
   performance, `ripwire-perf-target`; regression, `ripwire-write-tests`.
   A matching project copy takes precedence. Local suggestions start unchecked.
   Selecting one shares only its name, marked “if available on the executor”.
   The board never reads or sends the local file, absolute path or inventory
   to the AI provider. An isolated or remote worker may not have that skill.
3. **No guides available.** The verification scenario still travels with the
   issue. An unavailable repository does not block splitting. A model-supplied
   URL or unknown form value does not become a suggested guide.

## Ownership and extension

| Boundary | Owns | Does not own |
| --- | --- | --- |
| RepoDigest | Repository text for the prompt; separate tree-backed guide set | Machine inventory |
| AI registry / Intake | One primary verification method and a proposed scenario in the request language, in the existing two calls | Tool availability, pass/fail or merge authority |
| ReviewGuides | Method catalog; exact match, origin, selectable IDs and default selection | Reading or executing skill instructions |
| Composer / IssueBody | Owner's edits and selected references; language of the published child issue | Recalculating the plan on submit or retry |
| Executor / reviewer | Actual artifacts and checks on the delivered revision; independent judgment | Treating the proposed scenario as proof of execution |

To add a project-specific skill, commit its `SKILL.md` under the directory above;
no board change is needed. To add a cross-project verification method, extend
the method catalog, update the proposal guidance and cover the path from
proposal to posted issue. Keep machine discovery bounded.

A useful next experiment is to compare the proposed proof with what reviewers
actually needed: was it usable as written, edited, or missing a negative case?
Measure this on a few reviewed tasks before adding more methods or automated
approval. This release does not score reviewers or infer success from an
attachment or a checkmark.
