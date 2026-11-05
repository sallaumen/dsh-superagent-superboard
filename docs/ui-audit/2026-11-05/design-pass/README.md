# Design pass — Agent Board, adapted after #173 → #183

The original #171 layout has been adapted to the current LiveComponents. The old
single-file rendering was not restored. `BoardLive` still owns event handlers
and panel navigation; Header, Column, Card, Archive and AI own their regions.
The domain under `lib/agent_board/` was not changed.

| Severity | Region | Evidence | Correction |
|---|---|---|---|
| P2 | Merged history | [Before, #183 main](adapted-before-1600.png), [after](adapted-after-real-1600.png); `board_components/archive.ex` | Independent archive, five visible records, disclosure for the other 25 loaded records. “latest 30 loaded” is explicit because 30 is not a GitHub total. |
| P2 | Header | [Before](adapted-before-1600.png), [after](adapted-after-real-1600.png); `board_components/header.ex` | Identity, repository, health, age, actions and settings form distinct zones. Native settings disclosure remains open through LiveView patches. |
| P2 | Version | [After](adapted-after-real-1600.png); `components/system_panel.ex` | Semantic status chip, unknown values shown as unknown, update action emphasized only when the backend reports behind. |
| P2 | AI measurements | [Real AI panel](adapted-after-real-ai.png); `board_components/ai.ex`, `board_components/presentation.ex`; `board_live_test.exs` | Call identity and provider/model lead. Latency and usage are labeled. Missing values say unknown; zero stays zero. AI remains in the existing single-page dialog. |
| P3 | Dense empty lanes | [After](adapted-after-real-1600.png); `board_components/column.ex` | Four compact active lanes with counts. Merged history no longer extends the work grid. |

The before capture is the current #183 main result at 1600×900. The after
captures use the real saved board at `localhost:4002`, with 30 merged pulls.
The visible `sync_error` and unknown version state came from the backend. The
UI says “showing saved data” and reports that the saved data age is unknown.
The theme uses daisyUI tokens for both modes.

## Browser checks

WebKit headless, one tab, read-only UI interactions. The after capture above is
1600×900. [1366×768](adapted-after-real-1366.png),
[3440×1440](adapted-after-real-3440.png),
[375×812](adapted-after-real-375.png), and
[light 1600×900](adapted-after-real-light-1600.png) had no horizontal overflow.
Light/dark changed `data-theme` and the computed background. Enter expanded
Merged and displayed exactly 25 more records. Enter expanded Repositories;
Tab moved to Owner with a computed solid 2px focus outline. The AI dialog
opened and browser Back closed it without leaving the board.
No form was submitted, no task was created/archived and no message was sent.

An isolated `ui-fixture/read-only` test board was also checked at `localhost:4004`
for stale sync age, empty archive, queued cards, theme and keyboard behavior.
The fixture had 10-minute-old sync data while the socket was live, so the
staleness indicator did not imply fresh data. Its first navigation to
`127.0.0.1:4004` used a host outside the test socket origin and showed the
static/reconnecting state; `localhost` connected normally. Browser and task-owned
servers were closed after the review.

## Local gate

Actions billing is blocked. Under `PIPELINES.md`, the local gate is sufficient:
[`scripts/ci-local.sh all`](adapted-ci-local.log) exited 0 after adaptation.
The pipeline ran `mix gate` (compile with warnings as errors, format, strict
Credo and **175 passing tests**), Sobelow, `scripts/check_assets.sh`, asset
setup/build/deploy, and capability library validation with 20 passing tests.
`node --test test/assets/data_age_test.mjs` also passed 3 tests. Re-run the
workflow when billing is restored.

Tail of the local gate:

```text
Ran 20 tests in 0.767s

OK
OK: pipeline(s) verdes.
```
