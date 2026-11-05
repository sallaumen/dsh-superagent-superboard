# Board header panels

Baseline: `1c6e445`, headless WebKit, isolated `MIX_ENV=test` server and a clearly fictitious `fixture/header-lab` repository with six tasks and 30 merged PRs. No task was created, stopped, archived or messaged in the browser. The fixture was removed after review.

## Findings

| Severity | Region | Evidence | Correction |
| --- | --- | --- | --- |
| High | Header navigation | [Before at 1600px](header-workspace-before-1600.png): Settings was the only top-right entry; New task and Split a request occupied a detached strip. | Keep Split a request as the visible work action and group the remaining panels in the header. [After at 1600px](header-workspace-after-1600.png) |
| Medium | Settings information architecture | Activity and AI calls were under configuration, though they inspect current work. | Move both to [Panels](header-workspace-menu-1600.png). Settings now contains voice, repositories, appearance and version only. |
| Medium | Mobile action hierarchy | [Before at 375px](header-workspace-before-375.png): the action strip sat between health and board. | The work controls belong to the header and the menu overlays the page without changing the board layout. [After at 375px](header-workspace-after-375.png), [menu](header-workspace-menu-375.png) |
| High | Tablet header | [Before at 700px](header-workspace-before-700.png): the repository picker measured 2px wide. | Use two header rows below 1024px; the picker measured 255px at 700px and at least 205px across 650–900px. [After at 700px](header-workspace-after-700.png) |
| Medium | Keyboard menus | [Before at 900px](header-workspace-before-peer-menus-900.png): Enter could leave Panels and Settings open together. | Opening either disclosure closes its peer; Escape closes the remaining menu and keeps focus on its summary. [After at 900px](header-workspace-after-peer-menus-900.png) |

All existing `show_panel` event names, `phx-value-panel` payloads, button IDs, and dialog targets remain. The new disclosure closes when a panel opens and restores focus to its summary when that panel closes. The direct Split action restores focus to itself.

## Browser checks

| Check | Result |
| --- | --- |
| Panels with keyboard Enter, then Escape | Menu opened and closed; focus remained on its summary. |
| AI calls from Panels, then Escape | `panel-ai` opened with heading focus; menu closed; URL returned to the board; focus returned to Panels. |
| Split a request, then browser Back | `panel-intake` opened without leaving the page; Back closed it and restored focus to Split a request. |
| Direct Activity URL, then Close | Returned to the board URL without an extra history entry. |
| Switch repository with Panels open | Selected `fixture/header-other`, changed the board URL, and closed Panels. |
| 650/700/768/820/900px | Repository picker widths: 205/255/323/375/455px; no document horizontal overflow. |
| Keyboard-only switch from Panels to Settings | Only Settings remained open; Escape closed it and focused its summary. |
| 375px / 1600px / 3440px | No document horizontal overflow; ultrawide board retained its 1880px maximum width. [3440px](header-workspace-after-3440.png) |
| Light theme | Menu and controls used the theme tokens; `data-theme=light` and computed root background changed. [Light menu](header-workspace-menu-light-1600.png) |
| Browser console | Zero errors and zero warnings. |

The test fixture was removed: zero repositories, tasks, pull requests, comments and AI calls remain in `MIX_ENV=test`.

## Gate

`MIX_TEST_PARTITION=1 scripts/ci-local.sh all` passed after the menu and tablet adjustments: 323 tests, 0 failures; Credo, Sobelow, asset check/build/deploy and library check green. The expected audit error log comes from the failure-injection test in #229. CI remains blocked by billing; `PIPELINES.md` permits the local pipeline as the merge gate.
