# Intake readiness gate · 2026-11-05

Fixture isolated in `MIX_ENV=test`, `MIX_TEST_PARTITION=intake_visual_20261105`, repository `fixture/intake-visual`. The browser used headless WebKit at `http://localhost:4002` with a local `Req` plug. The plug returned `ready: false`, one open question, and, only if asked to split, one plausible task. It never called a model or GitHub.

| Finding | Before | After |
| --- | --- | --- |
| The refinement said `ready: false`, yet the board ran `propose_tasks` and exposed a `Create` action for an unready task. | [1600×900 screenshot](before-1600.png): open question and Create coexist. The accessibility snapshot also contained the task and Create button. | [1600×900 screenshot](after-1600.png): status explains that detail is needed, shows the open question, and offers no Create action. A focused test confirms only one AI call when the request is unready. |
| The clarification state must fit on a phone. | Same desktop finding; no distinct mobile layout change was made. | [390×844 screenshot](after-390.png): dialog width 352px, document width 390px with no horizontal overflow; status and question remain in the dialog. |

The after run reused the cached refinement from the same isolated fixture database. The independent `IntakeTest` uses a fresh sandbox and asserts exactly one `ai_calls` row, so it proves that the split stage was skipped; the screenshot proves what the user sees. `IntakeUITest` verifies the status and absence of Create. No issue or task was created. The task-owned browser and server were closed after capture.
