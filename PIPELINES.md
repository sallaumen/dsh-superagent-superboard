# PIPELINES.md — como e quando usar cada script

Este documento é a resposta a "qual script eu rodo agora?". Ele define os pipelines do repositório, o contrato de cada script (quando usar, ambiente, efeitos, saída) e a separação entre backend, frontend, biblioteca e o caminho misto de release.

## Visão geral

| Pipeline | O que valida | Script canônico | Alvo `make` | Job da CI |
|---|---|---|---|---|
| Backend | Código Elixir: dependências órfãs, warnings, formatação, credo, testes | `mix gate` | `make backend` | `backend` (4 partições) |
| Frontend | Assets: build e deploy de esbuild/tailwind | `mix assets.deploy` | `make frontend` | `frontend · assets` |
| Biblioteca | Integridade de `capabilities/` | `python3 capabilities/tools/validar_biblioteca.py` | `make library` | `biblioteca de capacidades` |
| Misto (release) | O caminho combinado de um deploy | sequência de release (abaixo) | `make release` | `release · caminho misto` |
| Todos | Os três pipelines juntos, antes de entregar | `make check` | `make check` | os três jobs |

Regra de ouro: **o alvo `make` e o job da CI executam os mesmos comandos** — local e CI não divergem.

## Matriz de scripts

| Script | Quando usar | Ambiente | Efeitos | Saída esperada |
|---|---|---|---|---|
| `mix lint` | Iteração rápida, sem banco | qualquer | nenhum (somente leitura) | format e credo verdes |
| `mix precommit` | Antes de commitar; corrige formatação | `:test` automático | formata arquivos em lugar; roda testes | formatação aplicada + gates verdes |
| `mix gate` | Antes de abrir PR; na CI (não modifica arquivos) | `MIX_ENV=test` | cria/migra o banco de teste | dependências sem órfãs + os três gates verdes |
| `mix deps.unlock --check-unused` | Revisar lockfile (parte do `mix gate` e do job gates da CI) | `:test` | nenhum | nenhuma dependência órfã |
| `mix assets.setup` | Primeira execução / CI frontend | `MIX_ENV=dev` | baixa binários tailwind/esbuild | ferramentas instaladas |
| `mix assets.build` | Ao alterar CSS/JS | `MIX_ENV=dev` | escreve `priv/static/assets/` | bundle gerado sem erro |
| `mix assets.deploy` | Validar o caminho de produção dos assets | `MIX_ENV=dev` | minifica + `phx.digest` | manifesto de digest gerado |
| `validar_biblioteca.py` | Ao alterar `capabilities/`; CI library | Python 3.10+ | nenhum (somente leitura) | `OK` com 0 erros |
| `test_validar_biblioteca.py` | Ao alterar o validador | Python 3.10+ | temporários | 20/20 testes |
| `make backend/frontend/library/release/coverage/check` | Entrada única por pipeline | máquina local | os dos scripts acima | cada pipeline verde |
| `make coverage` | Auditar lacunas de teste | máquina local | gera `cover/` (HTML) | relatório gerado; exit != 0 se a cobertura total ficar abaixo de 90% (threshold padrão do Elixir) |
| `scripts/ci-local.sh [pipeline]` | Pré-voo completo antes de abrir PR | máquina local | os dos scripts acima (release é opt-in) | todos os pipelines verdes |

O `scripts/ci-local.sh` é o pré-voo de PR: roda os mesmos comandos dos jobs da CI na ordem deles e falha no primeiro pipeline vermelho. Use `make` para um pipeline isolado durante o trabalho e `scripts/ci-local.sh all` (ou `release`) antes de entregar.

## Por que separar backend e frontend

- **Toolchains diferentes**: backend valida com `mix` (compilação + credo + testes com Postgres); frontend valida com as tarefas de assets do próprio `mix` (esbuild/tailwind são dependências `runtime: :dev`). Misturar os dois em um job escondia qual lado quebrou.
- **Falha atribuível**: o nome do job (`backend · partição 2`, `frontend · assets`, `biblioteca de capacidades`) diz o que quebrou sem abrir logs.
- **Ciclos independentes**: mudar CSS não precisa reprocessar o backend, e vice-versa.

## Quando usar o pipeline misto

O job `release` existe para o caminho que **precisa** dos dois lados juntos: o deploy. Ele constrói os assets no ambiente dev (onde esbuild/tailwind existem), compila produção com warnings como erro, digere os assets e monta o release (`mix release`). Use-o como smoke antes de um deploy e sempre que a integração backend×frontend for o risco da mudança — não como gate de todo PR (para isso os pipelines separados são mais rápidos e específicos).

## Se a CI não consegue rodar (sem token, billing ou runner)

Regra vinculante (também no AGENTS.md): **ao perceber que o GitHub Actions não inicia, não espere por ele e não fique re-disparando.** O pipeline local passa a ser o gate oficial e **suficiente**.

Como perceber:

- Jobs que falham em poucos segundos com **zero steps** e annotation de conta ("payments have failed / spending limit") = bloqueio de billing/token, não defeito no código.
- Nenhum check aparece no PR = o runner nunca foi atribuído.

O que fazer:

1. Pare de esperar e de re-triggerar runs (não adianta sem resolver o bloqueio).
2. Rode `scripts/ci-local.sh all` — ou o alvo `make` do pipeline afetado — e corrija até ficar verde.
3. Siga com a entrega (commit, PR, merge) usando a execução local como evidência; registre no PR que a CI estava indisponível e qual comando local foi executado.
4. Quando o bloqueio da conta for resolvido, rode a CI manualmente (`workflow_dispatch`) no último `main` para repor a verificação externa.

O objetivo da CI continua sendo verificar em ambiente limpo; a regra apenas evita travar entregas por um bloqueio de conta que está fora do repositório.

## Adotar este desenho em outro projeto

1. Copie a estrutura do `Makefile`: um alvo por pipeline, cada um mapeando para um job da CI com os mesmos comandos.
2. Copie `capabilities/tools/validar_biblioteca.py` e valide sua biblioteca de capacidades com `--root` (IDs de origem próprios; veja `capabilities/tools/README.md`).
3. Adapte o job de release à sua stack: construa assets no ambiente onde as ferramentas de frontend existem e monte o artefato no ambiente de produção.
4. Mantenha esta matriz atualizada quando um script novo aparecer — um script sem linha aqui não tem "quando usar" definido.

## Histórico

- Job único (`gates`) substituído por pipelines separados (PR #13); smoke de release adicionado (PR #14); `make` como entrada única por pipeline (PR #15); esta matriz criada em seguida. Guideline "CI indisponível → pipeline local é o gate" adicionada depois do bloqueio de billing da conta.
