# Contributing

## O fluxo

1. Crie uma branch a partir de `main` com nome no padrão `feat/…`, `fix/…`, `docs/…`, `chore/…`, `test/…` ou `ci/…`.
2. Faça commits pequenos com mensagens no imperativo explicando o porquê.
3. Valide localmente com o pipeline correspondente (abaixo).
4. Abra um PR para `main` preenchendo o [template](.github/pull_request_template.md).
5. O merge é squash em `main`; quando o PR cobrir uma mudança grande, prefira dividir em vários PRs menores do que um só difuso.

Toda mudança entra via PR na `main` — nunca por push direto.

## Validação antes do PR

Siga a [matriz de scripts em PIPELINES.md](PIPELINES.md#matriz-de-scripts)
para escolher os checks durante o trabalho e o pré-voo obrigatório de entrega.
Os comandos e sua distribuição entre os jobs estão documentados ali.

Quando o GitHub Actions não iniciar, aplique a
[regra de CI indisponível](PIPELINES.md#se-a-ci-não-consegue-rodar-sem-token-billing-ou-runner).

## Biblioteca de capacidades

Para adicionar ou alterar uma capacidade em `capabilities/`, siga [capabilities/README.md](capabilities/README.md) ("Adicionar uma nova capacidade") e registre a decisão em [capabilities/INCORPORACAO.md](capabilities/INCORPORACAO.md). Os comandos de validação estão em [capabilities/tools/README.md](capabilities/tools/README.md).
