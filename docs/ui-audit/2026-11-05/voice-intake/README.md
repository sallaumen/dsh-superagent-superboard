# Voice intake draft: visual evidence

Baseline: `9f9e8f4` (`main` before this change). The before images were captured
from the existing board at `http://127.0.0.1:4002` with the Split panel open.
The after images were captured from this worktree at
`http://127.0.0.1:4003/?panel=intake&repo=sallaumen%2Fo_colmex`. No request was
submitted and no real microphone was opened during the browser review.

| Viewport | Before | After |
| --- | --- | --- |
| 1366×768 | [before-1366.png](before-1366.png) | [after-1366.png](after-1366.png) |
| 3440×1440 | [before-3440.png](before-3440.png) | [after-3440.png](after-3440.png) |
| 375×812 | [before-375.png](before-375.png) | [after-375.png](after-375.png) |

WebKit accessibility snapshot: the native dialog retained its name and close
button; the request became a labeled multiline textbox; the selected
repository and the consequence of Split are visible. At 375px, typing kept
focus in the textbox, the page width stayed 375px, Escape closed the dialog
in-place, and the console reported zero errors. The dev-only live-reload frame
logged one TLS/clear-channel warning during the second capture; it did not
affect the dialog.

After the voice panel and read-only command PRs landed, the second WebKit pass
used the same worktree at port 4003. The [voice panel before this action](../voice-read-commands/voice-read-after-1366.png)
had only the read-only command button. The new secondary action appears in
[after-voice-1366.png](after-voice-1366.png),
[after-voice-3440.png](after-voice-3440.png), and
[after-voice-375.png](after-voice-375.png). Clicking it opened the prepared
intake draft shown in [after-draft-1366.png](after-draft-1366.png) and
[after-draft-375.png](after-draft-375.png).

This pass typed `Crie um painel de custo por modelo` into the command textarea,
observed the exact same value in the action's `phx-value-text` attribute, then clicked
Prepare coding request. The intake displayed that exact text and the selected
repository. Browser Back returned to the voice panel with the draft preserved
and focus on its heading. At 375px, document width equalled viewport width.
The console had zero errors and warnings. No Split, issue creation, real
microphone capture, or paid AI request was triggered by these browser actions.
LiveView tests cover the cross-panel transfer, no automatic AI call or task
creation, edit preservation after a board update, and stale repository
rejection. An actual device coexistence check with Wispr remains part of the
final release validation.
