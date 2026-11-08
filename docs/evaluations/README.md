# Avaliações do board — evidência

Rodadas da [campanha de avaliação](../board-ai-evaluation.md), cada uma com o
relatório lido por humanos e o ledger JSONL completo (perguntas, snapshots
fictícios, respostas, verificações e linhas de `ai_calls`).

> **Registro histórico.** Os números medem o modelo local e o corpus da rodada;
> não são nota do agente de programação nem dos provedores de produção.

| Rodada | Modelo | Resultado | Ledger |
|---|---|---|---|
| [2026-11-05 — avaliação local](2026-11-05-board-ai-local.md) | `qwen3.5:9b` local (Ollama) | 13 casos, 16/26 na rubrica de revisão humana | [JSONL](2026-11-05-board-ai-local.jsonl) |
| [2026-11-06 — títulos externos fora das perguntas agregadas](2026-11-06-board-ai-aggregate.md) | `qwen3.5:9b` local (Ollama) | 13 casos; proteção de título hostil aplicada antes do modelo | [JSONL](2026-11-06-board-ai-aggregate.jsonl) |

Nenhuma rodada criou tarefa, mensagem ou comentário real: banco de teste
dedicado e vazio, engine local, sem retry.
