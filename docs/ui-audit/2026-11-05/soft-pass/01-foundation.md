# Softer theme foundation

Baseline: `22f6d5f`, real saved board at `localhost:4002`, 1600×900. WebKit,
one task-owned tab, read-only interactions. The UI is for a maintainer scanning
agent work, sync health and recent merges. The direction is a calm work surface:
warm paper in light mode, soft slate in dark mode, readable task titles, and
monospace reserved for operational facts. The sync-failure line and loaded
history count remain prominent and truthful.

| Severity | Region | Evidence | Change |
|---|---|---|---|
| P2 | Whole board | [Dark before](01-before-dark.png), [dark after](01-after-dark.png); [light before](01-before-light.png), [light after](01-after-light.png) | Warm/slate daisyUI theme tokens replace cold black/white and saturated violet/orange. Semantic tokens remain distinct for error, warning and success. |
| P2 | Typography | Same captures; `assets/css/app.css`, `lib/agent_board_web/live/board_live.ex` | Sans for work titles and controls; mono for numbers, state, time and identifiers. The page no longer inherits monospace indiscriminately. |
| P3 | Small screen | [375×812](01-after-mobile.png) | No horizontal overflow; content order and controls remain available. |

Computed colors in WebKit confirmed actual light/dark theme switching. The
saved-data sync error stayed visible in both. The AI dialog opened and browser
Back closed it on the same page. No task action, form submit, speech or
version-check button was activated. The browser and server were closed after
capture. Local gate and asset validation are recorded below after execution.

## Local gate

`scripts/ci-local.sh all` exited 0: `mix gate` (compile warnings as errors,
format, strict Credo, tests), Sobelow, `scripts/check_assets.sh`, assets
setup/build/deploy and the capability-library validator with 20 tests.
`node --test test/assets/data_age_test.mjs` passed 3 tests. The full local
[gate log](01-local-gate.log) is the gate while Actions billing is blocked,
per `PIPELINES.md`.
