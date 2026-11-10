# A DeepSeek session on two models, 2026-11-10

Workflow: `debugging` (Elixir Agent Kit 0.8.0), small. What was left of the
"messages with no model" investigation after #586.

## What #586 settled

27 869 of 62 429 harness messages had no model because the reader only looked
at `model/selection`, which subagent transcripts do not have. #586 also reads
`request/context` and re-reads older files. Measured over all 408 transcripts
(event types and model ids only, no message text): every response also names
its model in `data.message.source.model`, and it differs from #586's reading in
1 message of 62 429. Nothing more to fix there.

## What was left

9 of the 408 sessions used two models. The ledger groups by model, so the rows,
the Executions tab and the daily spend priced them; the inspector header priced
a session as one model and left such a session unpriced, so its task read `≥`
or `—`. Now each model pays its own price, as in the ledger.

## Checked

| 2026-11-04 to 11-10 | |
|---|---|
| From the ledger, on a copy re-read from the real transcripts | US$ 122.343824, 134 of 134 executions complete |
| From the transcripts directly (`Harness.window/2`, this branch) | US$ 122.343827, complete, 62 429 messages |

Same tokens on both paths: 76 760 740 input, 41 168 848 output, 16 820 078 592
cache reads. The two totals differ by rounding only.

Not reconciled against DeepSeek's invoice or console.
