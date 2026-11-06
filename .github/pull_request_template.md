## O quê e por quê

- [ ] Descreve o problema que este PR resolve e a mudança em uma frase por commit relevante.
- [ ] Aponta para a origem quando houver (PR/issue anterior; ID de origem no Elixir Agent Kit).
- [ ] Workflow do Elixir Agent Kit aplicado: `<id do catálogo>` ou `NONE` (mudança delimitada só pelo contrato e pelos gates). Cite o arquivo lido.

## Pipelines afetados

Informe os pipelines afetados conforme a [matriz de scripts](https://github.com/sallaumen/agent-board/blob/main/PIPELINES.md#matriz-de-scripts).

## Validação

- [ ] Registre o commit validado, os comandos executados e seus resultados, incluindo o pré-voo exigido pela matriz.
- [ ] Testes novos ou ajustados quando a mudança muda comportamento; nenhum teste desativado para ficar verde.
- [ ] Nenhum artefato gerado pela validação entrou no diff.

## CI

Registre o estado da CI e a evidência correspondente. Se estiver indisponível,
siga o [procedimento canônico](https://github.com/sallaumen/agent-board/blob/main/PIPELINES.md#se-a-ci-não-consegue-rodar-sem-token-billing-ou-runner).
