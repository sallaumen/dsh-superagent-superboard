# What a merged task's inspector offers, 2026-11-10

Workflow: `direct-interactions` (Elixir Agent Kit 0.8.0), small. Audit finding 18.

| Action | Before the audit | Now | Why |
|---|---|---|---|
| Stop | offered | gone (since #542) | the issue is already closed: there is nothing to stop |
| Archive | offered | kept | it is what one does with finished work |
| Ask / the reply box | offered, with the hint for an open issue | kept, with a hint of its own | a person's comment on the closed issue resumes the ticket in the runner under the same mandate (`docs/decisions/0003-ciclo-de-vida-do-agente.md`, read in the runner's code, not verified live); the owner may want exactly that, and is told before sending |

- [01](01-merged-inspector-dark-en.png): arena-rogue #205, merged, on a copy of the real data. Actions "Ask, Archive"; the hint reads "Task #205 is merged. This message is posted on its closed issue and mentions the agent, which resumes the work on the same ticket." (Portuguese checked too.)
