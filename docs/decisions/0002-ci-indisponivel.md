# ADR 0002 — CI indisponível: o pipeline local é o gate suficiente

- **Decisão:** quando o GitHub Actions não consegue iniciar por bloqueio fora do repositório (sem token, sem runner, pendência de cobrança), não se espera pela CI: a validação local executada com evidência é o gate suficiente para seguir (commit, PR, merge), registrando a limitação e o comando executado. A CI é re-verificada via `workflow_dispatch` quando o bloqueio for resolvido.
- **Estado:** implementada.

## Problema e contexto

Os runners da conta ficaram bloqueados por pendência de cobrança (jobs falham em segundos com zero steps; annotation "payments have failed / spending limit"). Esperar pela CI travaria todas as entregas por uma condição de conta fora do repositório; re-disparar runs não muda o resultado e consome cota.

## Alternativas

| Alternativa | Benefício | Custo ou risco |
|---|---|---|
| Bloquear entregas até a CI voltar | Máxima confiança remota | Entregas paradas por tempo indefinido |
| Ignorar validação quando a CI não roda | Velocidade | Regressões sem nenhum gate |
| Gate local com evidência + re-verificação posterior (escolhida) | Entrega contínua com gate real | A verificação externa fica adiada |

## Escolha e consequência

- A regra é vinculante para agentes (AGENTS.md), para humanos (PIPELINES.md, CONTRIBUTING.md, template de PR) e para qualquer projeto que use a biblioteca de capacidades (contrato comum, seção 5).
- Como perceber a indisponibilidade está documentado: jobs com zero steps em poucos segundos + annotation de billing, ou check ausente.
- Salvaguardas: a indisponibilidade não dispensa os checks locais; o PR registra qual comando foi executado; a CI é re-verificada depois.

## Implantação e revisão

PRs #19 (dispatch manual e cancelamento de runs obsoletos), #37 (regra), #39 (template), #42 (contrato comum), #44 (CONTRIBUTING). Reconsiderar quando a conta tiver runners estáveis: a regra continua valendo para qualquer bloqueio equivalente, não apenas billing.
