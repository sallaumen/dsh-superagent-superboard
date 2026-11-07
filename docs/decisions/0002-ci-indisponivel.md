# ADR 0002 — CI indisponível: o pipeline local é o gate suficiente

- **Decisão:** adotar validação local com evidência como gate suficiente quando a CI estiver indisponível por bloqueio externo. O procedimento vigente está em [PIPELINES.md](../../PIPELINES.md#se-a-ci-não-consegue-rodar-sem-token-billing-ou-runner).
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

O gate continua obrigatório, mas sua execução remota pode ser adiada por um
bloqueio de conta. [PIPELINES.md](../../PIPELINES.md#se-a-ci-não-consegue-rodar-sem-token-billing-ou-runner)
mantém o diagnóstico e o procedimento; AGENTS.md, CONTRIBUTING.md e o template
de PR apontam para ele. A biblioteca reutilizável mantém o princípio geral no
[contrato comum](https://github.com/sallaumen/elixir-agent-kit/blob/v0.7.0/priv/library/CONTRACT.md#validate-the-changed-risk).

## Implantação e revisão

PRs #19 (dispatch manual e cancelamento de runs obsoletos), #37 (regra), #39 (template), #42 (contrato comum), #44 (CONTRIBUTING). Reconsiderar quando a conta tiver runners estáveis: a regra continua valendo para qualquer bloqueio equivalente, não apenas billing.
