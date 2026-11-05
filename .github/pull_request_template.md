## O quê e por quê

- [ ] Descreve o problema que este PR resolve e a mudança em uma frase por commit relevante.
- [ ] Aponta para a origem quando houver (ex.: IDs de origem na biblioteca de capacidades; PR/issue anterior).

## Pipelines afetados

- [ ] Backend (`lib/`, `test/`, `mix.exs`, `config/`) → `make backend`
- [ ] Frontend (`assets/`, `priv/static/`) → `make frontend`
- [ ] Biblioteca (`capabilities/`) → `make library`
- [ ] Caminho de release (`config/runtime.exs`, deploy) → `make release`

## Validação

- [ ] Pipeline local verde (marque os executados): `mix gate` / `make backend` / `make frontend` / `make library` / `make release` / `scripts/ci-local.sh all`
- [ ] Testes novos ou ajustados quando a mudança muda comportamento; nenhum teste desativado para ficar verde.
- [ ] `git status` limpo após a validação (sem artefatos de build no diff).

## CI

- [ ] CI verde, **ou**
- [ ] CI indisponível (sem token/billing, jobs falhando em segundos com zero steps): registre aqui o comando local executado como evidência — conforme a regra em [PIPELINES.md](PIPELINES.md#se-a-ci-não-consegue-rodar-sem-token-billing-ou-runner). Não espere pela CI nesse caso.
