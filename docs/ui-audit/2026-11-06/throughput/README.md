# Throughput per hour — 2026-11-06

The board gained a throughput strip under the digest: eight tiles that count
what the board recorded for the repository, per hour, so the owner can watch
the rates of one agent and then of several in parallel. The sources, windows
and known limits of every tile are in
[docs/maintainer-contract.md](../../../maintainer-contract.md#throughput);
the motion decision (one 600 ms tint on a value that changed, nothing on a
broadcast that changed nothing) is in [docs/ui-motion.md](../../../ui-motion.md).

## What was checked

Baseline `87511a9` (`main`), a development server of this branch on
`http://127.0.0.1:4003` reading the shared development database and the real
runner (the orchestrator API on `127.0.0.1:3082` and its sqlite), repository
`sallaumen/arena-rogue`. Headless WebKit through the Playwright MCP, one tab,
closed after the last capture. The captures show real data: the counts in them
are what the tables held at 22:36–22:38 (UTC−3), not a fixture.

| Capture | Viewport | What it shows |
|---|---|---|
| [after-1440.png](after-1440.png) | 1440 × 900, light | two rows of four tiles between the digest and the lanes; commits `7/h` after the first commit read, `+3` against the previous hour |
| [after-390.png](after-390.png) | 390 × 844 | two tiles per row; the cycle table and the parallelism tile take the whole row; `scrollWidth == 390`, nothing clipped but screen-reader-only text |
| [after-3440.png](after-3440.png) | 3440 × 1440 | one row of eight tiles, the strip as wide as the three lanes under it; `scrollWidth == 3440` |
| [after-dark-1440.png](after-dark-1440.png) | 1440 × 900, dark, `prefers-reduced-motion: reduce` | the tokens carry the strip; the tint on a changed value is off |

Observed in the browser, not inferred from the screenshots:

- The accessibility tree names every value: each sparkline is an `img` whose
  label lists the 24 hourly counts, oldest first; each bar has its clock span
  as a tooltip; the delta chip reads "+3 em relação à hora anterior" ("+3 against
  the previous hour"); the cycle tile is a table with a caption and row and
  column headers.
- With `prefers-reduced-motion: reduce` the computed `animation-name` of a
  value carrying `.is-changed` is `none`; with `no-preference` it is
  `ab-flow-change`, 0.6 s, `cubic-bezier(0.2, 0, 0.38, 0.9)`.
- Console: zero errors at every width. The one warning (`#board-connection`
  hook overwrites `handleEvent`) predates this change.
- Before the first commit read, the commits tile showed `?` with "ainda sem
  leitura dos commits" ("still no commit read yet"); after one sync it showed the count.
  The orchestrator answered `0 de 3` with `0 esperando` ("0 of 3", "0 waiting").

## Not observed

- The change tint on a live broadcast was verified by adding the class in the
  page and reading the computed animation, not by waiting for a real merge
  during the capture. The hook's compare is covered by
  `test/assets/throughput_test.mjs` (`node --test test/assets/throughput_test.mjs`).
- Several agents in parallel: the runner had one worker slot in use at most
  during this session, so the parallelism tile was only seen at `0 de 3`.
