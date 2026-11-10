# DeepSeek's published prices, each token at the rate of its hour, 2026-11-10

Workflow: `metrics-costs` (Elixir Agent Kit 0.8.0), large. Audit proposal P3c,
the owner's choice ("por horário").

## What the provider publishes

<https://api-docs.deepseek.com/quick_start/pricing>, read 2026-11-10. US$ per
1M tokens, peak / off-peak ("Off-peak rates are half of the peak rates"):

| Model | Input, cache hit | Input, cache miss | Output |
|---|---|---|---|
| `deepseek-flash` | 0.006 / 0.003 | 0.30 / 0.15 | 1.20 / 0.60 |
| `deepseek-v4-pro` | 0.044 / 0.022 | 1.32 / 0.66 | 3.96 / 1.98 |

Peak: 01:00 to 04:00 and 06:00 to 10:00 UTC, Monday to Friday, excluding
Chinese public holidays. The board's table held 0.28 / 0.42 for both models
and no price for cache reads.

## Metric definition

| Shown | Source | Unit | Rule | Unknown stays unknown |
|---|---|---|---|---|
| DeepSeek cost, everywhere the executor's cost appears | transcripts (inspector), `usage_messages` hours over `usage_ledger` rows (rows, Executions, daily), messages (summary of the day) | US$, estimated | each token at the published rate of its own hour (`Providers.peak?/1`, `at_full_rate/3`) | a message with no model has no price; a row or message with no time is priced off-peak and shown `≥` |

Holidays are priced as peak (the board has no such calendar): those days read high.

## Traced on a copy of the real data (2026-11-04 to 11-10)

| | Before | After |
|---|---|---|
| DeepSeek total | ≥ US$ 20 (cache reads at zero) | ≈ US$ 71.38, by summing the 132 priced executions |
| Hand computation from the raw messages, split by hour | | US$ 71.4 |
| Peak tokens (ledger split vs. raw messages) | | input 3 395 684, cache 1 289 492 096: equal |
| arena-rogue #208: row, Executions tab, inspector header | ≥ US$ 0.14 | ≈ US$ 0.40, 401 885 micro-US$ in all three, complete |

Of 134 DeepSeek executions, 115 are complete, 17 are minimums and 2 have no
price: 27.9 thousand messages record no model (6.5 + 0.85 billion cache
tokens), which the board does not guess. Every day still reads `≥` for them.

## Not done

- Board calls keep the price stored when they ran; new ones use these prices, with their whole prompt at the cache-miss rate (the provider's cache-hit count is not read).
- Not reconciled against DeepSeek's invoice or console.
- The prices are constants read on this date: a change on the page needs a new reading.
