# 4 — Icons, loading, flash and reduced motion

| Severity | Region | Evidence | Correction |
|---|---|---|---|
| P2 | Motion | `assets/css/app.css:156`; `core_components.ex:460` | Card/dialog/flash entry is opacity-only, 120 ms, with no action delay. Reduced-motion disables animations/transitions. Broadcasts do not replay card entry. |
| P2 | Loading | [Read-only panel open with simulated latency](04-loading.png) | Existing phx-click/submit loading state adds a dashed boundary and progress cursor. Existing submitting labels remain. |
| P2 | Icons | [Before](04-before.png), [after](04-after.png) | Clock = Activity, scissors = Split, CPU = AI, X = Close. Useful text remains. Shared Heroicons are decorative/aria-hidden; control names come from text or aria-label. No icon claims successful sync/model health. |
| P2 | Flash | [Duplicate behind the backdrop](04-flash-before.png), [single visible notice inside panel](04-flash.png) | The active panel owns visible feedback. Dismissal is immediate; global flash is hidden only while a modal is active. |

Computed WebKit results:

- Ordinary card animation: board-appear / **0.12s**.
- prefers-reduced-motion: animation **none / 0s**, transition **0s**.
- After broadcast: **0 animationstart events**, same card DOM nodes.
- Loading boundary: **dashed**. Test-only latency simulation disabled immediately afterwards.
- Error flash visibly inside the modal; global flash visibility hidden; dismissal succeeds.
  This error was produced only in the isolated fixture with an offline AI adapter;
  no real model request, GitHub task or message was submitted.
- Final light/dark checks: no horizontal overflow at **1366×768**, **3440×1440**,
  **375×812**. [1600×900](final-1600.png), [AI panel](final-ai-panel.png).
- Final console: zero errors or warnings; browser and task-owned servers closed.

`scripts/ci-local.sh all`: **172 tests, 0 failures**, strict checks, Sobelow,
check_assets.sh, assets.build/deploy, library validator and 20 tests.
[Full log](04-gate.log). After the final CSS-only duplicate-flash correction,
`scripts/ci-local.sh frontend` passed again: [log](04-frontend-final.log).
`node --test test/assets/data_age_test.mjs`: 3 passed.
Local gate substitutes billing-blocked CI according to PIPELINES.md.
