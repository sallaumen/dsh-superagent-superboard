# 3 — In-page panels and coherent history

| Severity | Region | Evidence | Correction |
|---|---|---|---|
| P1 | Reconnection | Repository form recovery re-fired `select` and closed the conversation, removing its unsent input. Regression test: `repository form recovery does not close the current panel`. [Recovery](03-reconnecting.png) | Selecting the current repository is a no-op. Browser recovery retained URL, open dialog, exact input DOM node, draft and focus. |
| P1 | Dialog lifecycle | WebKit retained an inert background when LiveView removed the native open attribute during a patch | LiveSocket preserves only the dialog's client-owned open attribute; the hook calls showModal/close. Content continues to receive normal LiveView patches. |
| P2 | Density and navigation | [Before](03-before.png), [after](03-after.png), [real board](03-real-board.png) | Activity, Split and AI have explicit tools above the board; their content opens on demand. Conversation includes full task title/body and messages. |
| P2 | History and keyboard | [Conversation](03-conversation.png), [Split](03-intake.png), [AI light](03-ai-light.png), [mobile](03-mobile.png) | Native dialogs with names, focus containment, Escape, return focus, and LiveView URL patches. Close uses Back for an owned panel entry, replace for direct URLs. |

WebKit observations after the fixes:

- Three AI open/close cycles: history.length **3, 3, 3**. No extra blank board entries.
- Direct panel URL: history.length **5 → 5** after Close.
- Back closes the conversation; Forward restores it; focus returns to `open-task-13`
  (fixture ID in that run). Eight consecutive Tab presses stayed inside the modal.
- During broadcast plus fixture task movement: one card per task, same input node,
  same focus, same unsent draft. The domain poller's cadence and idempotence tests
  also passed in mix gate (including the real 10-second scheduling test).
- Disconnect/connect: reconnecting feedback appears inside the open panel; same
  input node/value/focus remain after reconnect. No loading animation on broadcasts.
- Split draft survives closing/reopening. No request was submitted.
- Light/dark render; 375 px has no horizontal overflow. Final console: zero errors
  or warnings. Browser closed after each phase.

All original domain event names and payloads are retained. New presentation events
are show_panel/dismiss_panel. Invalid task URLs and cross-repository task IDs cannot
open a conversation. Flash feedback is also rendered inside the active modal, so it
is not obscured by the browser's top layer.

`scripts/ci-local.sh all` passed: **172 tests**, strict checks, Sobelow,
check_assets.sh, assets.build/deploy and 20 library tests. [Log](03-gate.log).
CI remains billing-blocked; local gate applies under PIPELINES.md.

## Repeat the isolated browser checks

The fixture creates only rollback-scoped records in a separate test database;
no real GitHub tasks/messages. It refuses any environment/partition other than:

```sh
MIX_ENV=test MIX_TEST_PARTITION=ui_review mix ecto.create
MIX_ENV=test MIX_TEST_PARTITION=ui_review mix ecto.migrate
mix assets.deploy
MIX_ENV=test MIX_TEST_PARTITION=ui_review PORT=4004 PHX_SERVER=1 \
  elixir --sname board_ui_review -S mix run scripts/ui_review_fixture.exs
```

Visit `http://localhost:4004/?repo=ui-fixture/read-only` in the configured WebKit.
The fixture's sandbox ownership timeout is explicitly infinite during this manual
session; stopping the task-owned process rolls the transaction back. The real
preview was also checked at 127.0.0.1:4002. Both servers were stopped afterwards.
