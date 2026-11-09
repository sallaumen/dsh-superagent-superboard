# Unified board layout — visual check

Fixture: `scripts`-style isolated test server on the `ui_unified` test database, seeded with one working repository (running ticket, blocked item, eight queued tasks, merges across seven days) and one idle repository (empty lanes, merges across seven days). The connection banner was hidden in the captures; the fixture server is not reachable from the browser's live socket, so the images show the server-rendered layout.

Measured inside each capture (container `main`):

| Capture | `main` | Lanes | Day columns | Throughput cells |
|---|---:|---:|---:|---:|
| `working-1920-dark.png` | 1696 px | 3 | 7 | 8 |
| `working-1920-light.png` | 1696 px | 3 | 7 | 8 |
| `working-1366-dark.png` | 1142 px | 2 | 4 | 4 |
| `working-760-dark.png` | 704 px | 1 | 2 | 2 |
| `working-390-dark.png` | 390 px | 1 | 1 | 2 |
| `idle-1920-dark.png` | 1696 px | 3 | 7 | 8 |
| `working-1920-inspector.png` | 1256 px | 2 | 4 | 4 |

The working and idle boards have the same DOM: `.ab-lanes` with `#sec-now`, `#sec-needs` and `#sec-queue`, then `#sec-log`, then `#fold-flow`. Only the lane height changes when a lane is empty.

The screenshots were captured with Playwright and Google Chrome. The throughput strip is the existing `Throughput` component; only its column count changed with the width of `main`.
