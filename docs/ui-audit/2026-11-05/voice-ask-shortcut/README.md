# Voice shortcut in the task conversation

## Finding and change

| Severity | Region | Before | Correction |
| --- | --- | --- | --- |
| High | Task conversation | Double Space on the focused conversation heading made **zero** microphone requests, so the voice Ask confirmation added in #226 was unreachable through the requested gesture. [1366px before](voice-ask-shortcut-before-1366.png) | Allow the gesture only on the conversation heading or neutral board focus. Keep text fields, buttons, settings, and other dialogs excluded. [1366px listening](voice-ask-shortcut-listening-1366.png) |
| Medium | Conversation Escape | Escape stopped the stream but also closed the conversation through the dialog's native `cancel` event. | Consume that one dialog cancellation while voice is active. Escape then stops the track with no upload; the next Escape closes the conversation. |

The recording stores the starting dialog, repository URL and browser URL. A change to any of them cancels the active recording. The final transcript remains editable, and the Ask action still requires a separate confirmation.

## Browser evidence

Headless WebKit, simulated microphone, recorder and transcription endpoint, fictitious test repository/task. No real microphone, message or task mutation was used.

| Check | Observed |
| --- | --- |
| Main before change, conversation heading focused, double Space | 0 `getUserMedia` calls. |
| Changed branch, same focus and gesture | 1 `getUserMedia` call and 1 recorder start. |
| Second double Space | 1 track stop, 1 simulated transcription upload; voice draft opened. |
| `Check command` for “What changed in this task?” | Confirmation showed “Ask task #42: What changed in this task?”; `Ask the agent` was **not** clicked. [Confirmation](voice-ask-shortcut-confirm-1366.png) |
| Double Space in “Message to the agent” | Two literal spaces in the input, no additional microphone request. |
| Escape while listening | Track stopped, 0 uploads, task conversation stayed open. A second Escape closed it. |
| 375px and 3440px | No document horizontal overflow. |
| Database after the read-only run | Task #42 still `queued`, `stopped=false`, `archived=false`; 0 comments, 0 AI calls and 0 voice action events. The isolated test fixture was then removed. |

Before/after screenshots: [1366 before](voice-ask-shortcut-before-1366.png) / [listening](voice-ask-shortcut-listening-1366.png), [3440 before](voice-ask-shortcut-before-3440.png) / [listening](voice-ask-shortcut-listening-3440.png), [375 before](voice-ask-shortcut-before-375.png) / [listening](voice-ask-shortcut-listening-375.png).

The full integrated read-only browser battery for all five voice PRs is in [voice-final](../voice-final/README.md). Physical coexistence with Wispr Flow and other macOS applications still needs a manual device check; WebKit media mocks cannot prove it.

## Local gate

`scripts/ci-local.sh all` passed: 319 tests, 0 failures; Sobelow complete; `check_assets: OK`; assets build and deploy complete; library check complete. Two existing warnings in `announcer_test.exs` and `providers_test.exs` appeared during tests and did not fail the gate. CI is blocked by billing; `PIPELINES.md` makes this local pipeline sufficient for merge while that persists.
