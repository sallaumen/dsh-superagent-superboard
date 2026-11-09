# Review and integration of the four PRs

> **Historical record — November 5, 2026.** Counts, captures and states
> describe the revisions identified in this document, not the current product.
> See the [audit index and sequence](README.md).

Dependency sequence: #154 → #158 → #161 → #164. The following PRs had their
base changed to `main` after the dependency was integrated. The new providers,
the structured output (#169/#170), the environment configuration and the
version panel that entered main after the original audit were preserved.

## Findings resolved in the review

- **SystemPanel tokens:** the new component had reintroduced hexadecimal colors.
  #154 includes the conversion to warning/success/info and the respective content
  tokens. Version and update actions preserved; not triggered during the visual
  review. Evidence in [01-theme](01-theme.md#review-for-merge).
- **Health documentation:** #161 updates AGENTS.md and README: absence of sync,
  sync failure and reconnection have distinct meanings. The README still said that
  `no sync yet` indicated an exception.
- **Textual conflict in #164:** the `check_version`/`update` events added to the
  LiveView collided with the new `intake` clause without AI. Both events and the
  protection clause before the normal intake were kept. No handler was lost.

## Local gates

| PR | Validated code | Result of scripts/ci-local.sh all |
|---|---|---|
| #154 | `415a732` | 160 Elixir tests, Sobelow, assets and library green |
| #158 | `331c876` | 160 Elixir tests, Sobelow, assets and library green |
| #161 | `ec6fe27` (+ documentation in `26896b1`) | 164 Elixir tests, Sobelow, assets and library green |
| #164 | `5f97600` | 168 Elixir tests, Sobelow, assets and library green |

Each run included format/credo/compile/dependencies/tests via mix gate,
scripts/check_assets.sh, assets.build/deploy and the 20 library tests.
Main received #169/#170 during the sequence; the final cumulative gate includes both.
The additions after the final gate are only this record and screenshots.

GitHub confirmed billing in the annotation of job 127201135118: the job did not start
due to a payment failure or spending limit. The local gate was used per
PIPELINES.md and the user's authorization; Actions was neither waited for nor re-triggered.
When billing is released, run workflow_dispatch on main.

## WebKit after resolution

Light/dark at 1366×768, 3440×1440 and 375×812: scrollWidth equal to the viewport width,
LiveView connected and the version panel above the columns. Disconnect/connect returned
`reconnecting → live`. Zero errors or warnings in the console. No mutating operations,
messages, execution of Update & restart or real audio. Own browser and server closed.

Captures: [1366 light](merged-review-light-1366.png),
[1366 dark](merged-review-dark-1366.png),
[3440 light](merged-review-light-3440.png),
[3440 dark](merged-review-dark-3440.png),
[375 light](merged-review-light-375.png), [375 dark](merged-review-dark-375.png).
