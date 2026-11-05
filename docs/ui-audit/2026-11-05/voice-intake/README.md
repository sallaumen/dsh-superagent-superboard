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
affect the dialog. The voice-draft banner and
the full double-Space flow await the preceding voice-panel PR for browser
verification; LiveView tests cover preparation, editing, refresh preservation,
and a stale repository rejection in this PR.
