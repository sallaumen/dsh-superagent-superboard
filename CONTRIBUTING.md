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

## Práticas compartilhadas

Siga [a política de propriedade e evolução](docs/agent/practices.md).
Melhorias reutilizáveis entram por PR no Elixir Agent Kit e chegam aqui por uma
versão fixada. Contratos específicos do board continuam em `docs/`. Não edite a
dependência nem recrie uma biblioteca local. `make library` valida a instalação.
