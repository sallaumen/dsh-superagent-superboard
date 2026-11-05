# AI call cost on the board

Baseline: #193 on main. The backend now records `cost_micros` for priced
provider/model pairs. It also stores zero for old calls and unknown prices, so
a zero cannot safely be presented as a zero-dollar charge.

| Severity | Region | Evidence | Change |
|---|---|---|---|
| P2 | AI call details | [Before](03-before-ai.png), [after dark](03-after-ai-dark.png), [after light](03-after-ai-light.png) | Added per-call estimated cost from the stored microdollar value, preserving all six decimal places where needed. The panel labels the value as an estimate from model rates. |
| P2 | Missing cost | [After dark](03-after-ai-dark.png); `board_components/presentation.ex` | Zero or missing recorded cost renders “unknown”; historical and unpriced calls do not imply free usage. |
| P3 | Small dialog | [375×812](03-after-ai-mobile.png) | Metrics wrap without horizontal overflow. |

The dark capture uses real saved calls: three newer calls have positive estimates
($0.000279, $0.000333 and $0.000306); two older calls show unknown. This is not
an invoice or a total across calls. Browser interactions were read-only: the AI
panel opened, theme changed and browser Back closed the panel on the same page.
WebKit console had 0 errors and 0 warnings. Browser and task-owned server were
closed. No domain file under `lib/agent_board/` was changed.

The UI test verifies one positive recorded cost and the unknown state for a
missing/zero measurement. Local gate evidence follows after execution.

## Local gate

`scripts/ci-local.sh all` exited 0: `mix gate` (compile with warnings as
errors, format, strict Credo and tests), Sobelow, `scripts/check_assets.sh`,
assets setup/build/deploy and library validation with 20 tests.
`node --test test/assets/data_age_test.mjs` passed 3 tests. The [full local
log](03-local-gate.log) is the gate while Actions billing is blocked, per
`PIPELINES.md`.
