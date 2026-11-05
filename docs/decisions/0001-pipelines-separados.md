# ADR 0001 — Pipelines separados por tecnologia, com um caminho misto de release

- **Decisão:** substituir o job único de CI por pipelines separados — backend (4 partições), frontend (assets), biblioteca de capacidades — e um job misto de release; cada pipeline tem um alvo `make` e um script de pré-voo que executam os mesmos comandos da CI.
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

- Backend usa `mix gate` local e partições `MIX_TEST_PARTITION` na CI; frontend usa as tarefas de assets com `MIX_ENV=dev` (esbuild/tailwind são dependências `runtime: :dev`); a biblioteca usa o validador Python.
- O job de release exercita o caminho combinado (assets dev → compile/digest/release prod), que é o único lugar onde os dois lados precisam se encontrar.
- O contrato é guardado por teste (`test/pipeline_contract_test.exs`) e documentado em `PIPELINES.md`; o `Makefile` mapeia cada alvo 1:1 para um job.

## Implantação e revisão

PRs #13, #14, #15, #16, #17, #18, #21, #38, #40. Reconsiderar se uma stack nova tornar a separação artificial (ex.: testes E2E que exigem os dois lados — eles pertencem ao job misto, não aos separados).
