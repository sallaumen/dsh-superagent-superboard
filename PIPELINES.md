# PIPELINES.md — como e quando usar cada script

Este documento é a resposta a "qual script eu rodo agora?". Ele define os pipelines do repositório, o contrato de cada script (quando usar, ambiente, efeitos, saída) e a separação entre backend, frontend, biblioteca e o caminho misto de release.

## Visão geral

| Pipeline | O que valida | Script canônico | Alvo `make` | Job da CI |
|---|---|---|---|---|
| Backend | Dependências órfãs, práticas dos agentes, warnings, formatação, credo, testes e Sobelow | `mix gate` + `mix sobelow --exit` | `make backend` | `gates` + `backend` |
| Frontend | Fontes de assets, setup, build e deploy | `scripts/check_assets.sh` + tarefas de assets | `make frontend` | `frontend · assets` |
| Biblioteca | Referências ao kit versionado | `mix agent_kit.check` | `make library` | `biblioteca de capacidades` |
| Misto (release) | O caminho combinado de um deploy | sequência de release (abaixo) | `make release` | `release · caminho misto` |
| Todos | Backend, frontend e biblioteca, antes de entregar | `scripts/ci-local.sh all` | `make check` | `gates`, `backend`, `frontend`, `library` |

Os comandos executáveis vivem em [Makefile](Makefile),
[scripts/ci-local.sh](scripts/ci-local.sh) e no
[workflow](.github/workflows/ci.yml). A CI distribui os checks de backend entre
`gates` (dependências, compilação, formato, credo e Sobelow) e `backend`
(testes em partições com `MIX_TEST_PARTITION`, cada uma com seu banco).
Localmente, `make backend` e o pré-voo executam a suíte inteira e Sobelow.
O frontend usa `MIX_ENV=dev`; `release` é um job separado na CI e opt-in no pré-voo.

Os testes em `test/pipeline_contract_test.exs` verificam aliases e comandos
esperados no workflow. Eles não comparam esta documentação nem todos os corpos
dos scripts: alterações nesses contratos exigem conferir os consumidores.

## Matriz de scripts

| Script | Quando usar | Ambiente | Efeitos | Saída esperada |
|---|---|---|---|---|
| `mix setup` | Preparar um checkout de desenvolvimento | `MIX_ENV=dev` | instala dependências, prepara banco com seeds e compila assets | app pronto para iniciar; fora da CI porque aplica seeds |
| `mix ecto.setup` | Criar/migrar e popular o banco de desenvolvimento | `MIX_ENV=dev` | escreve no banco; executa `priv/repo/seeds.exs` | banco e seeds preparados; não é gate |
| `mix ecto.reset` | Recriar deliberadamente o banco local descartável | `MIX_ENV=dev` | **apaga o banco** e executa `ecto.setup` | banco recriado; fora da CI e do pré-voo |
| `mix test` | Testar comportamentos; aceita arquivo e filtros | `:test` automático | cria/migra banco de teste antes da suíte | testes verdes; a CI usa partições |
| `mix lint` | Iteração rápida, sem banco | qualquer | nenhum (somente leitura) | format e credo verdes |
| `mix precommit` | Antes de commitar; aplica correções | `:test` automático | remove dependências órfãs do lockfile, formata e roda testes | formatação aplicada + gates verdes |
| `mix gate` | Checks de backend; a CI distribui seus passos entre jobs | executar com `MIX_ENV=test` | compila e cria/migra o banco de teste; não altera fontes | dependências, referências dos agentes, warnings, formato, credo e testes verdes |
| `mix sobelow --exit` | Scan de segurança; parte de `make backend` e do pré-voo | `MIX_ENV=test` | análise estática, sem corrigir fontes | scan concluído sem achados que reprovem o comando |
| `mix agent_kit.check` | Confere a instalação versionada das práticas para agentes (parte de `mix gate` e do job gates) | dev ou test | somente leitura; não inicia a aplicação nem chama modelos | índice e pontos de entrada consistentes com a dependência e configuração |
| `mix deps.unlock --check-unused` | Revisar lockfile (parte do `mix gate` e do job gates da CI) | `:test` | nenhum | nenhuma dependência órfã |
| `mix assets.setup` | Primeira execução / CI frontend | `MIX_ENV=dev` | baixa binários tailwind/esbuild | ferramentas instaladas |
| `mix assets.build` | Ao alterar CSS/JS | `MIX_ENV=dev` | escreve `priv/static/assets/` | bundle gerado sem erro |
| `mix assets.deploy` | Validar o caminho de produção dos assets | `MIX_ENV=dev` | minifica + `phx.digest` | manifesto de digest gerado |
| [scripts/check_assets.sh](scripts/check_assets.sh) | Ao mudar CSS/JS (primeiro passo do pipeline frontend) | máquina local | nenhum (somente leitura) | entradas presentes, pipeline tailwind configurado, JS autoral sem debug |
| `make help` | Descobrir os alvos disponíveis | `make` | nenhum | nomes dos alvos e referência a esta matriz |
| `make backend` | Checks de backend completos, incluindo Sobelow | fixa `MIX_ENV=test` | os de `mix gate` e Sobelow | equivalente aos checks dos jobs `gates` + `backend` |
| `make frontend` | Validar fontes e assets de produção | fixa `MIX_ENV=dev` | checks, setup, build e deploy de assets | equivalente ao job `frontend` |
| `make library` | Validar referências à dependência fixada | dev | somente leitura | equivalente ao job `library` |
| `make release` | Exercitar o empacotamento de produção | assets em dev; aplicação em prod | gera o release e sobrescreve o artefato anterior | equivalente ao job `release`; opt-in local |
| `make check` | Executar backend, frontend e biblioteca | ambientes definidos por cada alvo | os dos três pipelines | checks de PR verdes; não inclui release |
| `make coverage` | Auditar lacunas de teste | máquina local | gera `cover/` (HTML) | relatório gerado; exit != 0 se a cobertura total ficar abaixo de 90% (threshold padrão do Elixir) |
| [scripts/ci-local.sh](scripts/ci-local.sh) `[pipeline]` | Pré-voo completo antes de abrir PR | máquina local | os dos scripts acima (release é opt-in) | todos os pipelines verdes |
| [scripts/service.sh](scripts/service.sh) | Iniciar o servidor via launchd ou diagnóstico manual | `mix` no PATH; `MIX_ENV=dev` e `PORT=4099` por padrão; espera o Postgres em `AGENT_BOARD_DB_HOST`:`AGENT_BOARD_DB_PORT` (`127.0.0.1:5434`) por até `AGENT_BOARD_DB_WAIT` segundos (300), todos substituíveis pelo ambiente | espera o banco (`pg_isready`, ou `nc` sem ele) e sai com 75 se ele não responder, para o launchd tentar de novo; depois `deps.get`, `ecto.migrate` e inicia processo persistente com `PHX_SERVER=true`; acessa serviços configurados | servidor ativo; não é gate e não roda na CI |

Antes de entregar qualquer PR, rode **`scripts/ci-local.sh all`**. Ele executa
backend, frontend e biblioteca sequencialmente e falha no primeiro pipeline
vermelho. Durante o trabalho, use `make` para um pipeline isolado. Quando o
caminho de deploy mudar, execute também `scripts/ci-local.sh release`.

Pré-requisitos: dependências instaladas com `mix deps.get`, Elixir/OTP e `mix`
no PATH, Postgres acessível em `127.0.0.1:5434` com usuário/senha `board`,
`pg_isready` no PATH para o pré-voo de backend. A biblioteca usa Mix; seus testes
de conteúdo e instalador pertencem ao repositório do kit. Uso e códigos de saída:
alvo omitido equivale a `all`; sucesso retorna 0, alvo desconhecido retorna 2 e
falha de um comando interrompe a execução com status não zero.
A instalação do serviço está em [README.md](README.md#run-as-a-service); o pré-voo
não inicia nem reinicia o serviço.

## Por que separar backend e frontend

- **Toolchains diferentes**: backend valida com `mix` (compilação + credo + testes com Postgres); frontend valida com as tarefas de assets do próprio `mix` (esbuild/tailwind são dependências `runtime: :dev`). Misturar os dois em um job escondia qual lado quebrou.
- **Falha atribuível**: o nome do job (`backend · partição 2`, `frontend · assets`, `biblioteca de capacidades`) diz o que quebrou sem abrir logs.
- **Ciclos independentes**: mudar CSS não precisa reprocessar o backend, e vice-versa.

## Quando usar o pipeline misto

O job `release` existe para o caminho que **precisa** dos dois lados juntos: o deploy. Ele constrói os assets no ambiente dev (onde esbuild/tailwind existem), compila produção com warnings como erro, digere os assets e monta o release (`mix release`). Use-o como smoke antes de um deploy e sempre que a integração backend×frontend for o risco da mudança — não como gate de todo PR (para isso os pipelines separados são mais rápidos e específicos).

## Se a CI não consegue rodar (sem token, billing ou runner)

Regra vinculante, referenciada pelo AGENTS.md: **ao perceber que o GitHub Actions não inicia, não espere por ele e não fique re-disparando.** O pipeline local passa a ser o gate oficial e **suficiente**.

Como perceber:

- Jobs que falham em poucos segundos com **zero steps** e annotation de conta ("payments have failed / spending limit") = bloqueio de billing/token, não defeito no código.
- Nenhum check aparece no PR = o runner nunca foi atribuído.

O que fazer:

1. Pare de esperar e de re-triggerar runs (não adianta sem resolver o bloqueio).
2. Rode `scripts/ci-local.sh all` e corrija até ficar verde; inclua `scripts/ci-local.sh release` quando o caminho de deploy mudar.
3. Siga com a entrega autorizada na sessão usando a execução local como evidência; registre no PR que a CI estava indisponível e qual comando local foi executado.
4. Quando o bloqueio da conta for resolvido, rode a CI manualmente (`workflow_dispatch`) no último `main` para repor a verificação externa.

O objetivo da CI continua sendo verificar em ambiente limpo; a regra apenas evita travar entregas por um bloqueio de conta que está fora do repositório.

## Adotar este desenho em outro projeto

1. Copie a estrutura do `Makefile`: um alvo por pipeline, mantendo os checks locais equivalentes aos jobs correspondentes da CI.
2. Para a biblioteca, siga o [prompt de instalação do kit](https://github.com/sallaumen/elixir-agent-kit/blob/v0.6.0/docs/INSTALL_WITH_AI.md) e execute `mix agent_kit.check` após baixar as dependências.
3. Adapte o job de release à sua stack: construa assets no ambiente onde as ferramentas de frontend existem e monte o artefato no ambiente de produção.
4. Mantenha esta matriz atualizada quando um script novo aparecer — um script sem linha aqui não tem "quando usar" definido.

## Histórico

- Job único (`gates`) substituído por pipelines separados (PR #13); smoke de release adicionado (PR #14); `make` como entrada única por pipeline (PR #15); esta matriz criada em seguida. Guideline "CI indisponível → pipeline local é o gate" adicionada depois do bloqueio de billing da conta.

## The agent and the AI layer

Two systems run beside the board, and neither is on the board's critical path:

| System | What it does | Documented in |
|---|---|---|
| `dsh-superagent` | watches GitHub for `@sallaumen-agent`, turns the mention into a ticket, runs the executor, opens the PR | [`docs/agent/how-it-works.md`](docs/agent/how-it-works.md) |
| `AgentBoard.AI` | refines a request into a spec, splits it into tasks, answers questions, speaks the board | [`docs/ai-layer.md`](docs/ai-layer.md) |

The board **mirrors** both: the sync reads GitHub, the AI panel reads
`ai_calls`. Stop the board and both keep working.

