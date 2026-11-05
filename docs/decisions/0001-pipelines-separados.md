# ADR 0001 — Pipelines separados por tecnologia, com um caminho misto de release

- **Decisão:** substituir o job único de CI por pipelines separados — backend, frontend e biblioteca de capacidades — e um job misto de release. A distribuição vigente dos checks está em [PIPELINES.md](../../PIPELINES.md).
- **Estado:** implementada.

## Problema e contexto

A CI era um job único (`gates`) que misturava formatação, credo e testes sem cobrir o frontend (nenhum build de assets era exercitado) nem a biblioteca de capacidades. Uma falha não dizia qual lado quebrou; mudar CSS reprocessava o backend; e o desenvolvedor não tinha um comando local equivalente à CI.

## Alternativas

| Alternativa | Benefício | Custo ou risco |
|---|---|---|
| Manter job único | Simplicidade | Falha não atribuível; frontend/biblioteca sem cobertura; local × CI divergem |
| Pipelines separados + release misto (escolhida) | Falha atribuível, ciclos independentes, paridade local×CI | Mais jobs para manter |
| Pipeline misto para tudo | Menos arquivos | Perde a atribuição de falha; custo de contexto maior |

## Escolha e consequência

Os pipelines permitem atribuir falhas à tecnologia correspondente e executar
checks específicos durante a iteração. O release exercita a integração entre
assets e aplicação de produção. A matriz operacional, os ambientes e a relação
entre comandos locais e jobs são mantidos em [PIPELINES.md](../../PIPELINES.md).

## Implantação e revisão

PRs #13, #14, #15, #16, #17, #18, #21, #38, #40. Reconsiderar se uma stack nova tornar a separação artificial (ex.: testes E2E que exigem os dois lados — eles pertencem ao job misto, não aos separados).
