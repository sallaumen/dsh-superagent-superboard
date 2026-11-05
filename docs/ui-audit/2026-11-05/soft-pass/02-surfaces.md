# Calm board surfaces and controls

Baseline: #190 on main. Browser: real saved board at `localhost:4002`, headless
WebKit, one tab. This pass keeps the existing structure and actions while
making the work area easier to scan for long sessions.

| Severity | Region | Evidence | Change |
|---|---|---|---|
| P2 | Overall composition | [Dark before](02-before-dark.png), [after](02-after-dark.png); [light before](02-before-light.png), [after](02-after-light.png) | Grouped header, version, work area and creation form on calm token-based surfaces, with restrained radii and space between regions. |
| P2 | Controls | Same before/after | Softer buttons and fields, clearer selected theme, primary Open action; 44px general target remains. No events or payloads changed. |
| P3 | Ultrawide and mobile | [1366×768](02-after-1366.png), [3440×1440](02-after-3440.png), [375×812](02-after-mobile.png) | Content width capped at 1880px on ultrawide; no horizontal overflow at these widths. |
| P3 | AI dialog | [After](02-after-ai.png) | Rounded token-based dialog with the same data and navigation. |

WebKit confirmed 30 loaded merged records, five visible plus 25 in a keyboard
accessible disclosure, visible focus outline, dark/light switching and AI
panel Back closing on the same page. `prefers-reduced-motion: reduce` computed
`animation-name: none` and `transition-duration: 0s` on a board row. Browser
console had 0 errors and 0 warnings. No task, message, speech, version or
repository write action was used. Browser and task-owned server were closed.

The saved-data sync error and unknown version state in the screenshots came
from backend assigns. Styles reference daisyUI theme tokens, not hardcoded
component colors. Local gate evidence follows after execution.

## Local gate

`scripts/ci-local.sh all` exited 0, including `mix gate` (compile warnings as
errors, format, strict Credo and tests), Sobelow, `scripts/check_assets.sh`,
assets setup/build/deploy, and library validation with 20 tests. The separate
`node --test test/assets/data_age_test.mjs` run passed 3 tests.
[Full log](02-local-gate.log). This local gate is sufficient while GitHub
Actions billing is blocked, per `PIPELINES.md`.
