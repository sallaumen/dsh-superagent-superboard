# Board header panels

Baseline: `1c6e445`, headless WebKit, isolated `MIX_ENV=test` server and a clearly fictitious `fixture/header-lab` repository with six tasks and 30 merged PRs. No task was created, stopped, archived or messaged in the browser. The fixture was removed after review.

## Findings

| Severity | Region | Evidence | Correction |
| --- | --- | --- | --- |
| High | Header navigation | [Before at 1600px](header-workspace-before-1600.png): Settings was the only top-right entry; New task and Split a request occupied a detached strip. | Keep Split a request as the visible work action and group the remaining panels in the header. [After at 1600px](header-workspace-after-1600.png) |
| Medium | Settings information architecture | Activity and AI calls were under configuration, though they inspect current work. | Move both to [Panels](header-workspace-menu-1600.png). Settings now contains voice, repositories, appearance and version only. |
| Medium | Mobile action hierarchy | [Before at 375px](header-workspace-before-375.png): the action strip sat between health and board. | The work controls belong to the header and the menu overlays the page without changing the board layout. [After at 375px](header-workspace-after-375.png), [menu](header-workspace-menu-375.png) |

All existing `show_panel` event names, `phx-value-panel` payloads, button IDs, and dialog targets remain. The new disclosure closes when a panel opens and restores focus to its summary when that panel closes. The direct Split action restores focus to itself.

## Browser checks

| Check | Result |
| --- | --- |
| Panels with keyboard Enter, then Escape | Menu opened and closed; focus remained on its summary. |
| AI calls from Panels, then Escape | `panel-ai` opened with heading focus; menu closed; URL returned to the board; focus returned to Panels. |
| Split a request, then browser Back | `panel-intake` opened without leaving the page; Back closed it and restored focus to Split a request. |
| Direct Activity URL, then Close | Returned to the board URL without an extra history entry. |
| 375px / 1600px / 3440px | No document horizontal overflow; ultrawide board retained its 1880px maximum width. [3440px](header-workspace-after-3440.png) |
| Light theme | Menu and controls used the theme tokens; `data-theme=light` and computed root background changed. [Light menu](header-workspace-menu-light-1600.png) |
| Browser console | Zero errors and zero warnings. |

The test fixture was removed: zero repositories, tasks, pull requests, comments and AI calls remain in `MIX_ENV=test`.

## Gate

To be filled with the final `scripts/ci-local.sh all` result before merge. CI remains blocked by billing; `PIPELINES.md` permits the local pipeline as the merge gate.
