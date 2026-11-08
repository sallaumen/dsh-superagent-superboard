# Superagents por projeto: plano de gestão no board

**Estado:** proposta de arquitetura, sem código de produção nesta entrega.
**Data:** 2026-11-08.
**Escopo:** transformar a configuração manual de um `dsh-superagent`
(profile, banco SQLite, porta, processo e keepalive) em um recurso do board,
com vários projetos e vários donos de board.
**Fora de escopo agora:** suporte multi-repositório dentro de um único
superagent, rodar o superagent como processo filho do board, guardar token do
GitHub no board, expor a API na rede.

## 1. O problema real

Hoje o DeepSeek é o executor padrão do board (`Executors.default/0 == "dsh"`),
mas **quem executa** é um `dsh-superagent` externo, um por repositório. A
segunda instância do `o_colmex` foi criada à mão:

- profile `superagent-colmex`, porta 3083, state em
  `~/.dsh/state/superagent-colmex`;
- um `LaunchAgent` por profile (`ops/com.dsh.superagent*.plist`);
- configuração de repositório, CLI, executor, policy e prompts feita pelo
  painel/API do DSH;
- o board descobre os bancos por wildcard
  (`~/.dsh/state/superagent*/orchestrator.sqlite`) e a lista de repositórios
  pelo setting `dsh_repositories`.

Isso funciona para dois projetos de um dono, mas não é um produto operável:
não há provisionamento, status por projeto, start/stop por projeto, escala
de workers, validação de acesso, rollback nem isolamento entre donos.

## 2. Decisões de arquitetura propostas

### 2.1 Um board por dono; não um board multi-inquilino

“Mais pessoas usando o board na casa delas” deve significar **uma instalação
do board por pessoa**, com o banco Postgres/estado local daquela pessoa. Um
único board compartilhado exigiria autenticação, autorização por tenant,
criptografia de segredo, auditoria por ator e isolamento de processo — um
produto diferente, e a API atual escreve sem autenticação no localhost.

**Recomendação:** manter o board single-owner e documentar a instalação
repetível. Só considerar multi-tenant em uma fase futura, com autenticação e
um limite de confiança explícito.

### 2.2 Um superagent por repositório; escala é `maxWorkers`

O `dsh-superagent` é desenhado para **um repositório** por instância. Não se
deve rodar dois superagents no mesmo repositório: as notificações do GitHub,
o lock do estado e as sessões colidem.

“Aumentar o número de processos” significa **aumentar
`executor.maxWorkers`** daquele superagent (sessões concorrentes), não criar
vários orquestradores para o mesmo repo. O board deve dizer isso na tela:
“1 superagent, N sessões simultâneas”.

### 2.3 O board é o plano de controle, não o pai do processo

O board não deve iniciar `dsh` como filho direto. Ele fala com o **manager
oficial** do DSH (`scripts/dsh-superagent`) e com a **API de gestão** do
superagent:

- `start|stop|restart|status` por profile/porta;
- `PUT settings/executor` para `maxWorkers`, diretório e prepare;
- `GET state` para saúde, repositório, load e setup.

O processo continua em tmux, fora do board. Se o board reiniciar, o
superagent continua; quando o board volta, reconcilia o estado desejado com o
observado. Após reboot, o **único** `LaunchAgent` do board inicia o board, que
inicia os superagents desejados. Isso substitui N plists por projeto.

### 2.4 Um único adapter, testável

`AgentBoard.Superagents.Manager` é um behaviour com duas implementações:

- `AgentBoard.Superagents.DshManager` — comandos reais e API HTTP;
- `AgentBoard.Superagents.FakeManager` — testes, cria profiles/portas/estados
  temporários e simula start/stop/scale.

Nenhuma LiveView ou worker chama `System.cmd/3` diretamente. O manager é
injetado por configuração, como o `runner_launcher` dos runners.

## 3. Mapa de responsabilidades

| Conceito / tabela | Dono | Quem lê | Quem escreve |
|---|---|---|---|
| `repositories` | `Board` | `BoardLive`, `Routing`, `Superagents` | `Board` (ação `add_repository`) |
| `tasks` | `Board` | board, routers, relatórios | `Board`/`Actions` e overlays do sync |
| `superagents` | `Superagents` | board, `Routing`, `AgentState`, `Actions` | `Superagents` (via ações) |
| `superagent_events` | `Superagents` | UI de auditoria | `Superagents` |
| `runner_executions` | `Runners` | inspetor, Hoje | `Runners` (ação `dispatch_task`) |
| SQLite de tickets do DSH | processo DSH (externo) | `AgentState` (somente leitura) | DSH |
| USO/custos | `Usage` | painéis, router, resumo | leitores do ledger |
| GitHub (issues/PRs) | `Sync` | board | `Sync`/`Actions` |

Direção de dependência:

```
web (LiveView) → Superagents → Manager (behaviour) → DSH manager/API
web → Board → Repo
Routing → Superagents (estado observado) + Usage
AgentState → Superagents (lista de state dirs explícitos)
```

`Superagents` é o único dono da tabela `superagents` e do ciclo de vida. O
board não importa detalhes de `dsh`; o adapter é a fronteira.

## 4. Modelo de dados

### 4.1 `superagents`

Uma linha por projeto/repositório.

| Campo | Tipo | Regra |
|---|---|---|
| `id` | bigint | PK |
| `repository_id` | FK repositories | **unique**, um agente por repo |
| `profile` | string | unique; `superagent-<slug>` validado |
| `port` | integer | unique; faixa configurável, 127.0.0.1 |
| `state_dir` | string | root permitido; permissão 0700 |
| `desired_state` | enum | `running`, `paused`, `stopped` |
| `observed_state` | enum | `unknown`, `starting`, `ready`, `paused`, `error`, `stopped` |
| `observed_at` | utc_datetime | última leitura |
| `last_error` | text | motivo legível, sem segredo |
| `max_workers` | integer | 1..N; default 3 |
| `poll_seconds` | integer | 60..3600 |
| `setup_version` | integer | versão do template aplicado |
| `created_by` | string | ator local (dono) |
| timestamps | | |

Índices: `repository_id` unique, `profile` unique, `port` unique,
`(desired_state, observed_state)`.

### 4.2 `superagent_events`

Auditoria append-only: `superagent_id`, `action` (`provision`, `start`,
`stop`, `pause`, `resume`, `scale`, `delete`, `reconcile`, `error`), `from`,
`to`, `actor`, `detail`, `inserted_at`. A UI mostra os últimos eventos; o
registro de ações do board continua sendo o registro de decisões.

### 4.3 `AgentState` explícito

Remover o wildcard como fonte de verdade. `AgentState.snapshot/0` passa a
receber/ler os `state_dir` de `Superagents`:

```elixir
AgentState.read_normalized(Superagents.state_paths())
```

O wildcard atual é útil como migração, mas não serve para um board com
múltiplos donos: ele varre o home e pode ler um banco de outro produto.

### 4.4 Migração dos dois agentes atuais

Uma migração de dados cria as duas linhas (`superagent` → arena, porta 3082;
`superagent-colmex` → o_colmex, porta 3083), com os state dirs atuais. O
`LaunchAgent` do segundo profile pode ser removido depois que o board
reconciliar com sucesso os dois; até lá, os dois caminhos convivem.

## 5. Ciclo de vida e reconciliação

### 5.1 Estados

Desejado: `running`, `paused`, `stopped`.

Observado: `unknown`, `starting`, `ready`, `paused`, `error`, `stopped`.

Regras:

- `desired=stopped` → manager stop; observado `stopped`.
- `desired=paused` → `POST executor/pause {paused:true}`; observado `paused`
  (o processo fica vivo, sem pegar trabalho novo).
- `desired=running` → start se necessário; remover pause; observado `ready`
  quando `/state.health` e setup estão ok.
- `setup.problem != nil` → observado `error`; a UI mostra o problema e o
  comando/ação necessária; não fica reiniciando em loop.
- `unreachable` > 3 leituras → `error` com “não respondeu”; o reconciliador
  tenta `restart` com backoff (máx. 3) e depois para.
- `starting` por mais de X segundos → `error` de timeout, nunca “ready”
  otimista.

### 5.2 Reconciliador

Um `SuperagentReconciler` (GenServer ou Oban cron a cada 30–60 s):

1. lê linhas com `desired_state != observed_state` ou saúde vencida;
2. executa **uma** transição por linha, com lock lógico (`updated_at`/Oban
   unique);
3. grava evento e observado;
4. nunca bloqueia uma LiveView; o comando vai para Task/Oban com timeout;
5. na inicialização do board, lê todas as linhas `desired=running` e inicia
   as que estiverem `stopped/unreachable`, com jitter.

O manager já é idempotente (`start` acha um processo existente). O board
também usa unique por profile/porta e um `GenServer`/Oban unique para evitar
duas ações simultâneas.

### 5.3 Start/stop/pause/scale

Ações do registro (ver §7):

- `provision_superagent` — cria profile/state/porta, valida acesso, inicia,
  configura via API e grava a linha; rollback em falha.
- `start_superagent` — desired running; manager start; espera `/state`.
- `stop_superagent` — desired stopped; manager stop; preserva estado.
- `pause_superagent` / `resume_superagent` — pausa lógica no DSH.
- `scale_superagent` — `maxWorkers` via `PUT settings/executor`; valida faixa.
- `remove_superagent` — stop; arquiva state dir; não apaga dados por padrão.

## 6. Provisionamento de um novo projeto

Fluxo em uma ação vermelha confirmada, executado fora da LiveView:

1. **Validar** `owner/name`; o repo está no board? Não? oferecer
   `add_repository` antes.
2. **Validar bot**: `gh-agent api repos/:owner/:name` e `permission=write`;
   sem segredo no board, o CLI do bot fica no ambiente do DSH.
3. **Alocar** profile (`superagent-<slug>`), porta livre na faixa
   (`dispatch_superagent_port_start` etc.), state dir sob um root permitido.
4. **Criar profile** a partir de um template versionado (não copiar de
   `~/.dsh/profiles/superagent` cegamente): port, stateDir, model provider.
5. **Iniciar** via manager e esperar `GET /state`; timeout com rollback.
6. **Configurar** source GitHub (repo, CLI), executor (directory, prepare,
   `maxWorkers`), policy (lista permitida) e prompts (template + versão).
7. **Conferir** `setup.problem == nil`, health ready, e que o repo é o
   esperado.
8. **Gravar** `superagents`, evento `provision`; devolver o painel/porta e o
   link para o projeto.

O clone/prepare do projeto precisa de um diretório existente e limpo. O
board não deve clonar repositórios pessoais sem uma escolha explícita; o
formulário pede o caminho local ou oferece “usar `~/src/<name>`” com
confirmação.

### 6.1 Alocação de porta

Uma faixa por board (`3082..3182`, configurável), verificação de
`lsof`/bind e unique no banco. O profile novo nunca reutiliza uma porta de
uma linha `running`; uma linha `stopped` pode reutilizar após confirmação.

### 6.2 Rollback

Falha em qualquer passo depois do profile/state:

- `stop` best-effort;
- mantém state dir/logs para diagnóstico;
- grava `observed=error`, `last_error` e evento;
- não apaga o repo/tarefas;
- permite `retry` idempotente da ação.

## 7. Ações e contrato de confirmação

Toda ação nova entra em `AgentBoard.Actions`, com risco, frase com valores
reais, auditoria e teste em `actions_test.exs`.

| Ação | Risco | Efeito | Confirmação |
|---|---|---|---|
| `provision_superagent` | vermelho | cria profile/processo/porta/state e configura o DSH | frase com repo, profile, porta, caminho |
| `start_superagent` | vermelho | inicia um processo que pode gastar DeepSeek | frase com repo/profile |
| `stop_superagent` | vermelho | interrompe trabalho em andamento | frase com repo e tickets ativos |
| `pause_superagent` | amarelo | para de pegar trabalho novo, processo vivo | clique; desfaz com resume |
| `scale_superagent` | amarelo | muda `maxWorkers` | clique; −/+ desfaz |
| `remove_superagent` | vermelho | para e arquiva o profile/state | frase; não apaga por padrão |

A UI de projeto deve usar `AgentAction` (dois passos) para as vermelhas, como
o despacho local; nada começa no primeiro clique.

## 8. UI do board

Nova seção **Projetos / Superagents** (ou uma aba em Executores):

- lista por repositório: avatar/slug, status observado (bolinha +
  “ligado/desligado/pausado/erro”), porta, workers, último poll, tickets
  abertos, última mensagem de erro;
- botões: **Ligar**, **Parar**, **Pausar**, **Retomar**, **Workers −/+**,
  **Remover** (com confirmação);
- **Adicionar projeto**: repositório (select dos que o bot acessa), caminho
  local, workers iniciais, porta automática; um preview do que será criado;
- **DeepSeek** na tarefa: se o repositório tem um superagent `ready`, o
  compositor sugere DeepSeek e explica “1 agente, N sessões”; se está
  `stopped/error`, mostra o motivo e o botão de ligar;
- **Custo/uso**: DeepSeek em US$ estimado (ou “desconhecido”), sem somar com
  Claude/Codex; cota do Codex separada;
- mobile: cards empilhados, controles de 44 px, sem overflow.

## 9. Multi-dono e segurança

- **Recomendado:** uma instalação por pessoa, no usuário dela, com
  `~/.dsh`, `~/.agent_board`, Postgres e GitHub bot próprios. O board local
  continua sem autenticação de rede, mas escuta só `127.0.0.1`.
- **Se um board for compartilhado:** antes de qualquer projeto de outra
  pessoa, adicionar autenticação, papéis (owner/viewer/operator), isolamento
  por dono/repo, auditoria de ator e segregação de state dirs/portas. O
  modelo `superagents` ganha `owner_id`; `repositories` ganha tenant. Isso é
  um produto separado, não uma flag.
- **Segredos:** o board nunca guarda token do GitHub. O CLI do agente
  (`gh-agent`) e o login do DSH ficam no ambiente do dono; o board só
  verifica `api user`/permissão e grava o login público.
- **Fronteira de arquivo/processo:** profile/state/porta vêm de allowlist e
  validação; nada de `System.cmd` com string interpolada de input; argumentos
  em lista; state dirs 0700; root sob o home do usuário.
- **Rede:** superagent e board em `127.0.0.1`; sem túnel público.

## 10. Validação e testes

### 10.1 Testes de unidade/contexto (sem DSH real)

- `SuperagentsTest`: unique repo/profile/port; transições desejado/observado;
  rollback; delete preserva state.
- `FakeManagerTest`: provision cria profile/porta/state temporários; start
  idempotente; stop; scale; manager fora do ar; timeout.
- `ActionsTest`: cada ação nova, risco, frase, recusa sem confirmação,
  auditoria; nenhuma LiveView chama manager.
- `AgentStateTest`: lê só os state dirs do banco; não varre o home; dois
  repos, tickets separados; banco ausente.
- `RoutingTest`: DeepSeek só para repos com agente `ready`; pausado/erro/
  desligado aparece com motivo; compositor escolhe dsh quando ready.
- `BoardLiveTest`: card por projeto, ligar/parar/pausar/escala, confirmação;
  mobile 390 px.

### 10.2 Teste de integração com fake manager

Criar board → adicionar repo → provisionar → listar status → pausar →
retomar → escalar workers → parar → reiniciar o board (novo processo) →
reconciliar sem duplicar → remover. Tudo com state dirs temporários.

### 10.3 E2E real (uma vez, por máquina)

- Adicionar um projeto de teste com bot que tenha acesso.
- Provisionar pelo board; conferir `GET /state`, health, repo, porta.
- Criar uma tarefa de smoke; ver ticket no DSH e no board.
- Parar pelo board; conferir que o processo parou e que um novo start não
  duplica.
- Reiniciar o board; conferir reconexão e status.
- Medir tempo de provisionamento e falhas.

### 10.4 Critérios de aceitação

1. Um dono adiciona um repositório e provisiona o DeepSeek **sem editar
   arquivos à mão**.
2. O board mostra ligado/desligado/pausado/erro por projeto, com motivo.
3. Ligar/parar/pausar/retomar e workers funcionam e são auditados.
4. Um segundo projeto no mesmo board não interfere no primeiro (porta,
   state, tickets, tickets GitHub).
5. Reiniciar o board não mata superagents e não cria duplicata.
6. Falha de provisionamento não deixa processo órfão nem linha “ready”.
7. Outra pessoa instala o board na casa dela e repete o fluxo com o bot dela,
   sem mudar código.
8. Nenhum token no banco/log; nada escuta fora de localhost.

## 11. Fases e PRs

| Fase | Entrega | Prova |
|---|---|---|
| 0 | Este documento + ADR 0005 + decisões do dono | revisão aceita |
| 1 | Migração `superagents`/`superagent_events`; contexto; seed dos dois atuais; `AgentState` lê state dirs do banco | testes; board sobe com os dois |
| 2 | Manager behaviour + DshManager/Fake; status poller; cards read-only; reconciliação de status | testes + tela |
| 3 | Ações start/stop/pause/resume/scale; confirmações; UI | testes + E2E |
| 4 | Provisionamento (profile/porta/state/setup) + rollback + “Adicionar projeto” | fake + real |
| 5 | Remoção/arquivamento; boot reconciliation; remover plists por profile; docs de instalação | E2E reboot |
| 6 | Multi-dono: só se o dono escolher board compartilhado; auth/tenant/segurança | threat model + testes |

Cada fase é um PR squash, gate verde, serviço atualizado. A fase 1 não muda
a UI; a fase 4 é a única que cria processos externos.

## 12. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Duplicar superagent no mesmo repo | unique no banco + manager idempotente + lock |
| Porta ocupada | alocador + bind + erro claro + retry |
| Profile/state órfão | rollback para e arquiva; nunca apaga sem confirmação |
| Board reiniciado mata processo | processo em tmux, manager externo, reconciliação |
| Agente sem acesso ao repo | validação `gh-agent` antes de criar; UI explica |
| Setup pending infinito | timeout, `observed=error`, link do painel |
| Vazamento de token | nenhum token no board; CLI no home do dono |
| Board compartilhado sem auth | proibido até fase 6; uma instância por pessoa |
| Custo/consumo DeepSeek | uso estimado no ledger; sem somar moedas; teto por projeto no DSH |

## 13. Perguntas que precisam da sua decisão

1. **Uma instalação por pessoa** (recomendado) ou um board compartilhado
   multi-dono? Se compartilhado, a fase 6 vira pré-requisito, não opcional.
2. **Um bot por pessoa** (recomendado) ou um bot compartilhado? O bot é quem
   recebe as notificações; compartilhar mistura permissões.
3. **Auto-start no boot**: o board deve iniciar todos os projetos
   `desired=running`? Recomendado sim; o único LaunchAgent é o do board.
4. **Root dos state dirs**: `~/.dsh/state/superagent-<slug>` (atual) ou
   `~/.agent_board/superagents/<slug>`? O segundo desacopla do DSH, mas exige
   configurar o profile.
5. **Remoção**: arquivar o state (recomendado) ou apagar? O padrão não apaga.
6. **Faixa de portas** e máximo de workers por projeto.
7. **Aprovação do plano**: posso começar pela fase 1 (dados + leitura
   explícita), sem tocar na UI nem criar processos?

## 14. O que eu não faria

- Não rodar `dsh` como filho do board (`Port`/`System.cmd` que morre no
  restart).
- Não criar N `LaunchAgents` por projeto; um board, um reconciliador.
- Não varrer `~/.dsh` em produção; state dirs explícitos.
- Não guardar token do GitHub no Postgres.
- Não fingir que “mais processos” = mais superagents no mesmo repo; é
  `maxWorkers`.
- Não abrir a API para a rede antes de autenticação.
- Não apagar state/worktrees automaticamente na remoção.

## 15. Evidência do estado atual (baseline)

- `mix xref graph --format cycles --label compile-connected` → **No cycles found**.
- Segundo profile em `~/.dsh/profiles/superagent-colmex`, porta 3083,
  `repository sallaumen/o_colmex`, health ready, `problem none`.
- `AgentState.paths/0` hoje lê
  `~/.dsh/state/superagent*/orchestrator.sqlite` (wildcard) — **temporário**;
  a fase 1 troca por linhas explícitas.
- `dsh_repositories` em Configurações → Despacho local; compositor do
  `o_colmex` já sugere DeepSeek.
- `ops/com.dsh.superagent.colmex.plist` existe como prova; a fase 5 remove
  plists por profile em favor do reconciliador do board.
