# Settings, phase 3: Execution

Baseline: phase 2 (`8112787`). Preview: isolated test node on port 4008
(`MIX_ENV=test MIX_TEST_PARTITION=ui_review`), a temporary fixture that seeds
the usage ledger for the three executors, a 94% Codex weekly quota, the
board's own AI calls and `dispatch_monthly_usd = 0` so the no-cap warning
shows. Headless Chromium, locale `pt-BR`.

The fixture lives in `tmp/` and is not committed; it does not read or change a
real project or GitHub repository.

| Before (#472: Inspect + Local dispatch) | After: top |
|---|---|
| [before-desktop-dark.png](before-desktop-dark.png) | [desktop-execution-dark.png](desktop-execution-dark.png) |
| [before-desktop-light.png](before-desktop-light.png) | [desktop-execution-light.png](desktop-execution-light.png) |

| After: Codex block | After: DeepSeek, AI calls and save bar |
|---|---|
| [desktop-execution-codex-dark.png](desktop-execution-codex-dark.png) | [desktop-execution-bottom-dark.png](desktop-execution-bottom-dark.png) |
| [desktop-execution-codex-light.png](desktop-execution-codex-light.png) | [desktop-execution-bottom-light.png](desktop-execution-bottom-light.png) |

Phone, expanded section:

| Dark | Light |
|---|---|
| [mobile-execution-dark.png](mobile-execution-dark.png) | [mobile-execution-light.png](mobile-execution-light.png) |
| [before-mobile-dark.png](before-mobile-dark.png) | [before-mobile-light.png](before-mobile-light.png) |

Observed:

- The global pause is the first card; the switch reports `aria-checked`, and
  the copy says "Desligado" while it is off.
- Each executor is one block with its own currency: Claude Code "estimado" at
  list price, Codex "medido" with a `role="progressbar"` quota, DeepSeek
  "estimado, mínimo" with `≥ US$`. The daily bars are dashed when the day has
  no ledger row, never zero.
- The limits are per executor: monthly/task/model for Claude Code;
  reserve/time/model for Codex. The Codex time field moved out of the USD
  block. The monthly field is empty when there is no cap, and the no-cap
  warning shows the accumulated spend.
- The DeepSeek block has no controls; its card points to Projects.
- The AI calls table is compact and aligned; the connection state is text
  ("conexão não verificada"), not an uppercase label. An error call keeps its
  reason under the function.
- The save bar is sticky, says how many fields are unsaved, names them and
  offers Discard / Save limits.
- The Executors and AI Calls modals are no longer opened from Settings. The
  Activity modal is temporarily linked from System until phase 5 moves the
  list inline and groups it.
- The old `dsh_repositories` field is gone; the router now derives the
  DeepSeek repositories from Projects (see `routing_projects_test.exs`).
