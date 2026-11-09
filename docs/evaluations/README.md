# Board evaluations — evidence

Rounds of the [evaluation campaign](../board-ai-evaluation.md), each with the
report read by humans and the full JSONL ledger (questions, fictional snapshots,
answers, checks and `ai_calls` rows).

> **Historical record.** The numbers measure the local model and the corpus of
> that round; they are not a grade for the coding agent or for the production
> providers.

| Round | Model | Result | Ledger |
|---|---|---|---|
| [2026-11-05 — local evaluation](2026-11-05-board-ai-local.md) | `qwen3.5:9b` local (Ollama) | 13 cases, 16/26 on the human review rubric | [JSONL](2026-11-05-board-ai-local.jsonl) |
| [2026-11-06 — external titles out of the aggregate questions](2026-11-06-board-ai-aggregate.md) | `qwen3.5:9b` local (Ollama) | 13 cases; hostile-title protection applied before the model | [JSONL](2026-11-06-board-ai-aggregate.jsonl) |

No round created a real task, message or comment: dedicated empty test database,
local engine, no retry.
