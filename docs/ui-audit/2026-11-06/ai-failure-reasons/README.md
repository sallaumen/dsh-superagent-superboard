# AI call failure reasons

Baseline: `origin/main` at `9fc9fb1`. WebKit screenshots used a disposable test
database (`MIX_TEST_PARTITION=9`) with five recorded AI calls. No model or board
action was sent. The fixture contains two successful calls and three failures:
`:usage_limit`, `malformed_output`, and one missing reason.

| Severity | Region | Evidence | Correction |
| --- | --- | --- | --- |
| Medium | Panels → AI calls | [Before, 1600 × 900](before-1600.png): the three `ERROR` rows only show status and metrics; `AgentBoard.AI` records the reason in `lib/agent_board/ai.ex:70-78`, `:138`. | [After, 1600 × 900](after-1600.png): each failed row shows the recorded reason; a missing value says `Reason not recorded`. |

Additional screenshots: [375 × 812, dark](after-375.png) and
[3440 × 1440, light](after-light-3440.png). The AI panel remains scrollable on
mobile. Both widths had document `scrollWidth` equal to viewport width. The
light/dark switch changed `data-theme`, and the error treatment uses daisyUI
tokens (`--color-error`, `--color-base-100`, `--color-base-content`). WebKit
reported no console warnings or errors.

Keyboard: opening the panel focuses its title. Escape closes it, removes the
`panel` URL parameter, and restores focus to the Panels menu summary after the
next animation frame. This change adds no control or keyboard interaction.

Validation: `MIX_TEST_PARTITION=10 mix test test/agent_board_web/live/board_live_test.exs`
(61 tests, 0 failures). Full local preflight is recorded in the PR.
