# Contributing

## O fluxo

1. Crie uma branch a partir de `main` com nome no padrão `feat/…`, `fix/…`, `docs/…`, `chore/…`, `test/…` ou `ci/…`.
2. Faça commits pequenos com mensagens no imperativo explicando o porquê.
3. Valide localmente com o pipeline correspondente (abaixo).
4. Abra um PR para `main` preenchendo o [template](.github/pull_request_template.md).
5. O merge é squash em `main`; quando o PR cobrir uma mudança grande, prefira dividir em vários PRs menores do que um só difuso.

Toda mudança entra via PR na `main` — nunca por push direto.

## Validação antes do PR

| Mudança | Comando |
|---|---|
| Código Elixir (`lib/`, `test/`, `mix.exs`, `config/`) | `make backend` (ou `mix gate`) |
| Assets (`assets/`, `priv/static/`) | `make frontend` |
| Biblioteca de capacidades (`capabilities/`) | `make library` |
| Caminho de deploy/release | `make release` |
| Antes de entregar qualquer PR | `scripts/ci-local.sh all` |

O que cada script faz e quando usar está em [PIPELINES.md](PIPELINES.md). Os testes de contrato em `test/pipeline_contract_test.exs` fixam os aliases e o workflow — se você mudar `mix.exs` ou `.github/workflows/ci.yml`, atualize o teste junto.

## CI

A CI roda os mesmos comandos dos pipelines locais em cinco jobs (gates, backend em 4 partições, frontend, library, release).

Se a CI não consegue rodar (sem token, billing ou runner), **não espere por ela**: o pipeline local é o gate suficiente. A regra completa — como perceber, o que fazer, quando re-verificar — está em [PIPELINES.md](PIPELINES.md#se-a-ci-não-consegue-rodar-sem-token-billing-ou-runner).

## Biblioteca de capacidades

Para adicionar ou alterar uma capacidade em `capabilities/`, siga [capabilities/README.md](capabilities/README.md) ("Adicionar uma nova capacidade") e registre a decisão em [capabilities/INCORPORACAO.md](capabilities/INCORPORACAO.md). O validador (e seus testes) são gates obrigatórios para qualquer mudança lá.
