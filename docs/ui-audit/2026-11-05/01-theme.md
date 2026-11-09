# Audit: theme and accessibility

> **Historical record — November 5, 2026.** Counts, captures and states
> describe the revisions identified in this document, not the current product.
> See the [audit index and sequence](README.md).

Baseline: `52113d4` (main, including #152). Headless WebKit, 2026-11-05.
`mix setup` passed. Port 4002 belongs to the checkout `/Users/tavano/src/agent_board`;
it was preserved. This checkout was served with `PORT=4003 mix phx.server`.
Real data was only read. The `fixture` page is rendered HTML with in-memory structs,
without inserting tasks or AI calls. It does not represent a connected LiveView session.

Direction: an operational console for following agents, preserving the mono typography,
the five columns and the emphasis on tasks/blocks. Refine readability, no redesign.

| Severity | Region | Evidence before | Fix |
|---|---|---|---|
| P1 | Contrast | [Light](baseline-light-1366.png), [forms](baseline-forms.png). Primary/content: 2.75:1 light, 4.13:1 dark; success/base: 2.31:1 light; error/base: 2.94:1 dark. | Adjust the canonical tokens, preserving light orange and dark violet. Primary/content is now 5.38:1 and 5.36:1. Secondary text uses 75% instead of 40/60%. |
| P2 | Theme | No `[data-phx-theme]` rendered; [header](baseline-dark-1366.png). The function existed but was not called. | System/Light/Dark control with names, `aria-pressed`, persistence and support for the system preference. |
| P2 | AI and loading | `board_live.ex` used `text-[#e8a33d]`; `app.js` had `#29d` and an RGBA shadow. [AI](baseline-mobile-ai.png). | `text-warning` and a progress color derived from `--color-primary`. Literal colors stay in the token definitions; unrouted Phoenix art and vendors stay out of this scope. |
| P2 | Keyboard/forms | [Fixture](baseline-fixture.png): fields relied on placeholders, inconsistent focus and 25px actions. | Explicit names for title/details/message, shared focus and controls with a 44px minimum height. |

Light/dark captures recaptured at commit `80e3ee9`, with transitions finished.
After: [light](theme-after-light.png), [dark](theme-after-dark.png),
[fixture](theme-after-fixture.png), [keyboard focus](theme-keyboard-focus.png).

Verified: click and keyboard in the themes, aria-pressed, reload, System + media change
to dark, LiveView connected and zero console errors. Contrast calculated with colors
resolved by the WebKit canvas (sRGB); it is not a certification of every combination.

Local gate: `scripts/ci-local.sh all` (includes `MIX_ENV=test mix gate`,
`scripts/check_assets.sh`, `mix assets.build`, assets.deploy and library).
151 Elixir tests, zero failures. CI unavailable due to billing as reported;
we neither waited for nor re-triggered Actions. Rerun workflow_dispatch when released.

## Review for merge

Integrated with `main` at `0b5d09d`. The new SystemPanel was preserved above the
columns and migrated from hexadecimal colors to semantic tokens, including the
Update & restart button. The visual test uses synthetic data and does not trigger an
update. Captures: [before](version-before-review.png), [light after](version-after-review.png),
[dark after](version-after-review-dark.png).
