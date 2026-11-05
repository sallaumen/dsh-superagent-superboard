# Empty work lanes and merged PR history

Baseline: `49935eb` on `main`; headless WebKit at `http://localhost:4002/?repo=fixture%2Fempty-history`. The isolated `MIX_TEST_PARTITION=7` fixture had **zero tasks and 30 merged PRs**. A second fictitious repository had one task in each active lane to check fixed sizes. No browser action created, stopped, archived or messaged a real task. The fixture was removed after review.

## Finding and correction

| Severity | Region | Evidence | Correction |
| --- | --- | --- | --- |
| Medium | Board with empty active lanes and 30 saved merges | [1600px before](empty-history-before-1600.png): 256px allocated to four empty lanes, 288px to the PR history; only four history rows intersected its scroll region, with blank viewport below. | Fixed active lanes at 224px and PR history at 464px, independent of card count. Seven history rows intersect the region. [1600px after](empty-history-after-1600.png) |
| Medium | Mobile path to recent work | [375px before](empty-history-before-375.png): four empty lanes sit before the merged list. | When **all four task counts are zero** and at least one merged PR is loaded, the first lane offers “View merged PRs.” The native same-page link targets a focusable history region. [375px after](empty-history-after-375.png) |

The board remains an instrument panel for repository work: dark and light theme tokens, monospace signals, fixed-height lanes, and a separate scroll region for history. No counts or task state are inferred from the browser.

## Browser checks

| Check | Observed |
| --- | --- |
| 1600×900, zero tasks / 30 PRs | Active lanes 224px; archive 464px; seven rows intersect the archive scroll region, up from four. |
| Same viewport, one task per lane | Active lanes still 224px and archive still 464px; Open, Stop and Archive remained visible in the Running card. |
| 1366×768 / 3440×1440 | No document horizontal overflow. [1366 before](empty-history-before-1366.png) / [after](empty-history-after-1366.png); [3440 before](empty-history-before-3440.png) / [after](empty-history-after-3440.png). |
| 375×812 | No horizontal overflow. The mobile active-lane area stayed at 801px and the archive at 320px; the new shortcut is visible in the first empty lane. |
| Keyboard on shortcut | Enter reached `#merged-column` on the same page; Tab entered `#merged-list`; End scrolled the list to its end. |
| Populated lanes | The shortcut was absent when any task count was nonzero. |
| Header Panels → Activity | Keyboard Enter opened the existing dialog, Escape returned to the board URL and focused Panels. |
| Light theme | Shortcut remained readable with theme token colors. [375px light](empty-history-after-light-375.png). |
| Browser console | Zero errors and zero warnings. |

The isolated fixture was removed: zero repositories, tasks, pull requests, comments and AI calls remain in test partition 7.

## Gate

After rebasing onto `c2d6a9b` (PRs #235 and #236), `MIX_TEST_PARTITION=8 scripts/ci-local.sh all` passed: **338 tests, 0 failures**, Sobelow complete, `check_assets: OK`, assets build/deploy complete and library check green. The expected audit error log came from the failure-injection test in #229. CI is blocked by billing; `PIPELINES.md` permits the local pipeline as the merge gate.
