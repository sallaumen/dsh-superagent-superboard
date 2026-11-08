# Auditorias de UI — evidência histórica

> **Registro histórico.** Contagens, capturas e estados descrevem as revisões
> da época da auditoria, não o produto atual.

Cada rodada registra base, método (WebKit headless, fixtures isolados) e o gate
local que passou. Capturas sem relatório próprio ficam nomeadas aqui para não
se perderem.

## 2026-11-05 — auditoria principal e passadas paralelas

A [auditoria principal](2026-11-05/README.md) correu em quatro PRs encadeados
com relatório e capturas por parte:

- [01 — tema, tokens, contraste e foco](2026-11-05/01-theme.md)
- [02 — densidade, títulos, Activity e responsividade](2026-11-05/02-layout.md)
- [03 — saúde, reconexão e contagens verdadeiras](2026-11-05/03-health.md)
- [04 — sucesso/erro, contexto de conversa, AI e voz](2026-11-05/04-actions.md)
- [05 — revisão para integração](2026-11-05/05-merge-review.md)

Passadas específicas, com relatório próprio:

| Pasta | O que revisou |
|---|---|
| [design-pass](2026-11-05/design-pass/README.md) | Adaptação do layout às LiveComponents atuais (após #173→#183) |
| [round2](2026-11-05/round2/README.md) | Segunda revisão visual sobre o app real (componentes, frescor, painéis, feedback) |
| [soft-pass](2026-11-05/soft-pass/01-foundation.md) | Fundação visual ([02 — superfícies](2026-11-05/soft-pass/02-surfaces.md), [03 — custo da IA](2026-11-05/soft-pass/03-ai-cost.md)) |
| [parallel-pass/reconnect](2026-11-05/parallel-pass/reconnect/README.md) | Reconexão em profundidade |
| [parallel-pass/cards](2026-11-05/parallel-pass/cards/) | Cartões (capturas pareadas) |
| [parallel-pass/css-cleanup](2026-11-05/parallel-pass/css-cleanup/) | Limpeza de CSS (capturas pareadas) |
| [parallel-pass/settings](2026-11-05/parallel-pass/settings/) | Menu de configurações (capturas pareadas) |
| [empty-board-history](2026-11-05/empty-board-history/README.md) | Raias vazias e histórico de PRs mesclados |
| [header-panels](2026-11-05/header-panels/README.md) | Painéis do cabeçalho |
| [intake-readiness](2026-11-05/intake-readiness/README.md) | Gate de prontidão do intake |
| [voice-command](2026-11-05/voice-command/README.md) | Captura de voz por duplo Espaço |
| [voice-actions](2026-11-05/voice-actions/README.md) | Confirmação de ações de voz |
| [voice-answer](2026-11-05/voice-answer/README.md) | Resposta natural do board |
| [voice-ask-shortcut](2026-11-05/voice-ask-shortcut/README.md) | Atalho de voz na conversa da tarefa |
| [voice-intake](2026-11-05/voice-intake/README.md) | Rascunho do intake por voz |
| [voice-presence](2026-11-05/voice-presence/README.md) | Indicador de presença da voz |
| [voice-read-commands](2026-11-05/voice-read-commands/README.md) | Comandos de voz somente leitura (PR #223) |
| [voice-final](2026-11-05/voice-final/README.md) | Bateria integrada de UX de voz |

Pastas só com capturas (sem relatório): `attention-menu`, `create-panel`,
`fixed-scroll`, `merge-trend`, `merged-pagination`, `settings-menu`,
`task-pagination`.

## 2026-11-06 — rodadas focadas

| Pasta | O que revisou |
|---|---|
| [ai-failure-reasons](2026-11-06/ai-failure-reasons/README.md) | Motivos de falha das chamadas de IA |
| [archive-history](2026-11-06/archive-history/README.md) | Resposta sobre histórico de arquivamento |
| [throughput](2026-11-06/throughput/README.md) | Faixa de vazão por hora sob o digest |
