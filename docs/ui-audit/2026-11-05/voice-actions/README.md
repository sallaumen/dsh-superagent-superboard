# Voice action confirmation review — 2026-11-05

## Isolated visual fixture

The screenshots use `fixture/voice-visual`, task `#42 Review the deploy check`, in `agent_board_test`. The task and repository were removed after the review; the test database returned to 0 repositories and 0 tasks. The WebKit browser only checked the draft, preview and Cancel. It did not click Confirm, send a message, or call GitHub.

| Viewport | Before: main at `5332622` | After: PR #225 |
| --- | --- | --- |
| 1366×768 | [before](before-1366.png) | [after](after-1366.png) |
| 3440×1440 | [before](before-3440.png) | [after](after-3440.png) |
| 375×812 | — | [after](after-375.png) |

The baseline shows an editable draft without an action review. The result shows a separate confirmation naming the task, repository and actual effect. The initial check button is hidden while the confirmation is pending, so the choices are Cancel or Confirm stop. At 375 px there was no document overflow. The confirmation controls have text names and a token-based 2 px `:focus-visible` outline.

## Browser observations

- A form submit with `stop task #42` opened the review without changing the task.
- Cancel removed the review and preserved the draft. Direct test-DB verification after the browser run returned `{queued, false, false, []}` for state, stopped, archived and activity events.
- In the successful `localhost` session, the browser console had 0 errors and 0 warnings. An initial attempt using `127.0.0.1` against the test server was rejected by Phoenix's test-environment WebSocket origin check; navigation to the configured `localhost` origin restored the LiveView connection. This did not affect the development server.

## Server-side verification

LiveView tests use `Req.Test` for GitHub. They cover preparation without a write, Cancel, draft edit, repository switch, stale task, confirmation once, failed Stop and forged client payload. The Ask flow inherited from #226 was hardened: it ignores the client question, checks the server's reviewed target and draft, and removes the action after one send. Its test waits for the background rehearsal answer before ending the sandbox owner.

The WebKit run used a fictitious test task. Device coexistence with Wispr remains a physical Mac check; browser mocks cannot establish it.
