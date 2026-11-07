# Symphony (openai/symphony) × a nossa plataforma de agentes

- **Data da análise:** 2026-11-06.
- **Objeto:** `openai/symphony` em `be10a1b` (2026-09-15, último commit; igual ao release `v0.0.3` e ao prerelease `nightly`).
- **Método:** clone de leitura num diretório próprio do scratchpad (dado não confiável: nenhum script, `mix` ou `make` do clone foi executado); `gh api`, `gh pr list`, `gh run list` e `git log` para os números; leitura dos nossos dois repositórios (`dsh-superagent-prototype` e este board). Caminhos do Symphony são relativos à raiz do clone; caminhos nossos levam o prefixo `dsh:` (protótipo) ou são relativos a este repositório.
- **Pergunta:** migrar para o Symphony, trazer peças, ou seguir como estamos.
- **Notas de pesquisa completas** (quatro arquivos, com o comando de cada número): pasta de notas da sessão, `research_notes/Symphony versus nossa plataforma/`. Este documento é o destilado.

## Resumo

**Não migrar. Seguir com a nossa plataforma e trazer cinco ideias do Symphony, começando pela política versionada em arquivo e pelo "workpad" estruturado.**

Três fatos decidem:

1. **O Symphony só fala com o Codex.** O único cliente de agente é `SymphonyElixir.Codex.AppServer` (JSON-RPC sobre stdio); não há abstração de provedor, nem campo `model` no schema — o modelo é uma flag do próprio Codex dentro de `codex.command` (`elixir/WORKFLOW.md:34`). Migrar significa trocar DeepSeek por Codex/OpenAI e reescrever 1.071 linhas de protocolo para qualquer outro agente.
2. **O Symphony não persiste nada.** Todo o estado (running, claimed, blocked, retries, tokens) vive na memória do GenServer `Orchestrator`; reiniciar apaga a fila de retry e o mapa de bloqueios (`elixir/README.md:33-36`, `SPEC.md` §14.3). O nosso board existe justamente porque lê o SQLite do agente e guarda histórico em Postgres; sobre o Symphony ele não teria o que espelhar além de um snapshot JSON.
3. **É um protótipo de uma pessoa, sem canal de suporte.** Autodeclarado "low-key engineering preview" e "prototype software intended for evaluation only"; 47 commits, 72 % de um autor; 4 commits nos últimos 3 meses; issues desativadas; 51 discussões com zero respostas de qualquer conta da OpenAI; 0 PRs externos mesclados; 52 dias sem commit; o relato de que a `v0.0.3` quebra com o Codex atual (discussão #134, 2026-10-26) está sem resposta.

O que vale a pena trazer está no desenho, não no binário: o `WORKFLOW.md` (política e prompt versionados no repositório, recarregados a quente), o comentário único "workpad" por issue, as regras de reconciliação (issue fechada no meio do run → parar; revalidar antes de despachar), a limpeza de workspaces e PRs órfãos em estado terminal, a telemetria por run (tokens, turnos, último evento, stall) e o `SPEC.md` como checklist de conformidade para auditar o nosso ciclo de vida.

## 1. O que o Symphony é

### 1.1 Posicionamento

"Symphony turns project work into isolated, autonomous implementation runs, allowing teams to manage work instead of supervising coding agents" (descrição do repositório). O README oferece duas opções: **"Option 1. Make your own"**, mandar o seu agente de código implementar o `SPEC.md`; e **"Option 2. Use our experimental reference implementation"** em Elixir (`README.md:21-28`). O aviso de topo diz "Symphony is a low-key engineering preview for testing in trusted environments" (`README.md:11`); o README do Elixir diz "prototype software intended for evaluation only and is presented as-is. We recommend implementing your own hardened version based on `SPEC.md`" (`elixir/README.md:6-8`); e a CLI só sobe com o flag `--i-understand-that-this-will-be-running-without-the-usual-guardrails` (`elixir/lib/symphony_elixir/cli.ex:8-9,111-126`).

O produto principal é o **`SPEC.md`** (2.312 linhas, "Status: Draft v1 (language-agnostic)", normativo com RFC 2119): define um "scheduler/runner e leitor de tracker" cuja fronteira é explícita — "Ticket writes (state transitions, comments, PR links) are typically performed by the coding agent through provider-native tools ... A successful run can end at a workflow-defined handoff state (for example `Human Review`), not necessarily `Done`" (`SPEC.md:36-44`). Não-objetivos: "Rich web UI or multi-tenant control plane", "General-purpose workflow engine", "Built-in business logic for how to edit tickets, PRs, or comments" (`SPEC.md:60-69`).

### 1.2 Linguagens e stack

| Item | Valor | Fonte |
|---|---|---|
| Linguagens (bytes, API do GitHub) | Elixir 914.026; Python 19.585; CSS 8.252; Shell 657; Makefile 650; Dockerfile 600 | `gh api repos/openai/symphony/languages` |
| Python | um único arquivo, `.codex/skills/land/land_watch.py` (helper assíncrono que chama `gh`); não é runtime | `find . -name '*.py'` |
| Elixir / OTP | `elixir: "~> 1.19"`; `mise.toml`: `erlang = "28"`, `elixir = "1.19.5-otp-28"` | `elixir/mix.exs:8`, `elixir/mise.toml:1-3` |
| Dependências de runtime | `phoenix ~> 1.8.0` (1.8.4), `phoenix_live_view ~> 1.1.0` (1.1.25), `bandit ~> 1.8` (1.10.3), `req ~> 0.5`, `jason`, `yaml_elixir ~> 2.12`, `solid ~> 1.2` (templates Liquid), `ecto ~> 3.13` (só `embedded_schema` para validar config; sem `ecto_sql`) | `elixir/mix.exs:70-87`, `elixir/mix.lock` (39 pacotes) |
| Empacotamento | `burrito ~> 1.5` (`only: :prod`), 4 alvos: `macos_arm64`, `macos_x86_64`, `linux_arm64`, `linux_x86_64` | `elixir/mix.exs:106-120` |
| Tamanho | 51 `.ex` (13.070 linhas em `elixir/lib`); 31 `.exs` (15.275 linhas em `elixir/test`) | `wc -l` |

Sem Phoenix, LiveView e Bandit o serviço perderia só o dashboard web; o núcleo depende de Req, Jason, YamlElixir, Solid e Ecto-schema.

### 1.3 Arquitetura

Aplicação OTP com um único processo de autoridade e N tasks efêmeras:

- `SymphonyElixir.Application` sobe, `one_for_one`: `Phoenix.PubSub`, `WorkflowStore`, `AgentRuntimeSupervisor`, `HttpServer`, `StatusDashboard` (`elixir/lib/symphony_elixir.ex:35-51`).
- `AgentRuntimeSupervisor` (`one_for_all`) agrupa um `Task.Supervisor` e o GenServer `Orchestrator`: se o scheduler cair, todos os agentes caem junto (`elixir/lib/symphony_elixir/agent_runtime_supervisor.ex:15-33`).
- `Orchestrator` (1.990 linhas) é o único mutador de estado: `running`, `claimed`, `blocked`, `retry_attempts`, `completed`, `codex_totals`, `codex_rate_limits`, tudo em memória (`elixir/lib/symphony_elixir/orchestrator.ex:29-44`).
- `AgentRunner` executa um item: `Workspace.create_for_issue` → hook `before_run` → sessão Codex com N turnos → hook `after_run` (`elixir/lib/symphony_elixir/agent_runner.ex:22-56`).
- `Tracker` é um behaviour de **leitura** (`fetch_issues_by_states/1`, `fetch_issues_by_ids/1`) com adapters compilados `asana`, `github`, `gitlab`, `jira`, `linear`, `memory`; "The orchestrator only depends on the read callbacks" (`elixir/lib/symphony_elixir/tracker.ex:2-31`).
- `Codex.AppServer` (1.071 linhas): cliente mínimo do protocolo `codex app-server` (JSON-RPC 2.0 sobre stdio).
- `WorkflowStore` relê o `WORKFLOW.md` a cada 1 s por `{mtime, size, phash2}`; reload inválido mantém o último bom; inválido no boot impede subir (`elixir/lib/symphony_elixir/workflow_store.ex:13,66-75,169-180`).
- `PromptBuilder` renderiza o corpo do `WORKFLOW.md` com Solid (`strict_variables`, `strict_filters`) e as variáveis `issue` e `attempt` (`elixir/lib/symphony_elixir/prompt_builder.ex:8-25`).

Fluxo de dados (texto):

```
WORKFLOW.md ─(poll 1s)─▶ WorkflowStore ─▶ Config (schema Ecto tipado)
                                              │
Tracker API ◀─ fetch_issues_by_states(active) ┐▼
            ◀─ fetch_issues_by_ids(running) ──┤ Orchestrator (GenServer)
                                              │  tick: reconcile running/blocked
                                              │        → validate → fetch → sort → dispatch
                                              │  :DOWN normal → retry de continuação (1 s)
                                              │  :DOWN anormal/stall → backoff 10 s·2^(n-1) ≤ 5 min
                                              ▼
                                   Task.Supervisor.start_child
                                              ▼
                                   AgentRunner.run(issue, attempt, worker_host)
                                     ├ Workspace.create_for_issue (root/<key>, hook after_create)
                                     ├ hook before_run
                                     ├ AppServer: bash -lc "unset <segredos> && exec codex app-server"
                                     │   initialize → thread/start{approvalPolicy,sandbox,cwd,dynamicTools}
                                     │   turno 1: prompt renderizado · turno n: "continuation guidance"
                                     │   item/tool/call → adapter.execute_agent_tool (host-side, com credencial)
                                     │   após cada turno: refetch da issue; segue só se ativa e roteável
                                     └ hook after_run
```

### 1.4 Modelo de execução

**Como recebe trabalho.** Só polling; não há receptor de webhook em lugar nenhum (o router só expõe dashboard e `/api/v1/*`, `elixir/lib/symphony_elixir_web/router.ex:17-41`). A cada `polling.interval_ms` (default 30 s; a OpenAI usa 5 s) o Orchestrator reconcilia os runs ativos, busca as issues nos `active_states`, ordena por `priority` 1..4, depois `created_at` mais antigo, depois `identifier` (`orchestrator.ex:796-814`), revalida cada candidata por id antes de lançar ("Skipping stale dispatch after issue refresh", `orchestrator.ex:907-938`) e despacha enquanto houver slots: `agent.max_concurrent_agents` (10), limite por estado (`max_concurrent_agents_by_state`) e limite por host SSH. Elegível = estado ativo e não terminal, `dispatchable` (definido pelo adapter: no GitHub, "não é PR"; no Linear, assignee bate e nenhum bloqueador aberto), todas as `required_labels`, não está em `running`/`claimed`/`blocked` (`orchestrator.ex:816-868`). `POST /api/v1/refresh` antecipa um ciclo.

**Como executa.** Workspace `<workspace.root>/<chave sanitizada>` por issue, reutilizado entre runs; hooks `after_create` (só na criação; falha aborta), `before_run` (falha aborta a tentativa), `after_run` e `before_remove` (falhas ignoradas), com `sh -lc`, cwd no workspace e `hooks.timeout_ms` 60 s (`elixir/lib/symphony_elixir/workspace.ex:15-52,397-418`). Validação anti-escape: canonicaliza caminhos, rejeita symlink que sai do root (`workspace.ex:483-510`; `app_server.ex:150-176`). O Codex sobe como `Port` com `bash -lc "unset <nomes de segredo> && exec <codex.command>"` (`app_server.ex:192-228`); handshake `initialize` → `thread/start` (uma thread por run, com `approvalPolicy`, `sandbox`, `cwd`, `dynamicTools`) → `turn/start` por turno (`app_server.ex:275-366`). O `turn_timeout_ms` (1 h) é tempo de **silêncio**, reinicia a cada mensagem; `stall_timeout_ms` (5 min) sem evento mata o worker e reagenda (`orchestrator.ex:581-639`). Aprovações são auto-concedidas **só** com `approval_policy: "never"`; com o default (mapa `reject`) qualquer pedido de aprovação, input livre ou elicitação MCP falha o turno e a issue vai para o mapa `blocked` em memória (`app_server.ex:55,565-721,1035-1070`; `orchestrator.ex:659-664,757-779`). Até `agent.max_turns` (20) turnos por sessão; o turno 1 leva o prompt completo, os seguintes só um texto curto de continuação (`agent_runner.ex:101-154`). Saída normal → retry de continuação em 1 s; anormal → `min(10 s × 2^(n-1), max_retry_backoff_ms = 5 min)`, sem teto de tentativas (`orchestrator.ex:13-14,1232-1243`). Tokens: deltas sobre totais absolutos por thread (`thread/tokenUsage/updated.total`), nunca `last_token_usage`; somados por issue e globalmente, mais `seconds_running` e o último payload de rate limit (`elixir/docs/token_accounting.md`; `orchestrator.ex:1725-1797`).

**Como entrega.** O runtime não tem nenhuma escrita no tracker nem no GitHub. "Done" para o Symphony é só "a issue saiu dos `active_states`" (claim liberado, workspace mantido) ou "entrou em `terminal_states`" (worker morto, workspace apagado) — reconciliação a cada tick (`orchestrator.ex:421-441`). Abrir PR, comentar, mover estado e mesclar são tarefas do agente, ditadas pelo prompt do `WORKFLOW.md` e pelas skills em `.codex/skills/`. No fluxo de referência: `Todo` → `In Progress` → PR anexado, label `symphony`, checks verdes → `Human Review` (**não** é estado ativo: o worker para e o workspace fica) → humano move para `Merging` → o agente roda a skill `land` em loop até `gh pr merge --squash` → `Done`; `Rework` = fechar o PR, apagar o workpad, branch nova (`elixir/WORKFLOW.md:7-11,107-116,237-263`; `.codex/skills/land/SKILL.md:11-19,97-98`). A única escrita do Symphony em si é o hook `before_remove` do workflow de referência, `mix workspace.before_remove`, que fecha PRs abertos da branch quando a issue chega a estado terminal sem merge (`elixir/lib/mix/tasks/workspace.before_remove.ex:43-110`).

### 1.5 Integrações

| Integração | O que existe | Fonte |
|---|---|---|
| Linear | GraphQL, páginas de 50, `inverseRelations` para `blocked_by`, `assignee: me`; tool `linear_graphql` (passthrough cru) | `elixir/lib/symphony_elixir/linear/{client,agent_tool}.ex` |
| GitHub Issues | REST `GET /repos/{o}/{r}/issues` (`state`, `per_page=100`, `sort=created`); estados só `open`/`closed`; PRs não despacháveis; `blocked_by` sempre `[]`; **sem** GraphQL nem Projects; tool `github_api` (GET/POST/PATCH/PUT/DELETE em path relativo) | `github/client.ex:105-221,344-347`, `github/adapter.ex:11-12`, `github/agent_tool.ex:8-36` |
| GitLab Issues | REST v4, estados `opened`/`closed`, `dispatchable` sempre `true`; tool `gitlab_api` | `gitlab/{client,adapter,agent_tool}.ex` |
| Jira Cloud | `POST /rest/api/3/search/jql`, `bulkfetch`; links "Blocks" viram `blocked_by`; tool `jira_rest` (path obrigatório `/rest/api/3/`) | `jira/client.ex:92-152,312-356` |
| Asana | tasks por projeto, estado = nome da seção; tool `asana_api` | `asana/client.ex:98-227` |
| Chat / notificação | **nenhuma** (grep por slack, discord, webhook, telegram, teams, pagerduty, smtp: vazio). A "notificação" é o comentário `## Codex Workpad` no tracker | `elixir/WORKFLOW.md:86-87,295-329` |
| Modelo / provedor | **só Codex** (`codex.command`, default `codex app-server`); zero menções a `OPENAI_API_KEY`, Anthropic, Claude ou Ollama; auth é a do CLI (`~/.codex/auth.json`) | `config/schema.ex:181`, `elixir/WORKFLOW.md:34` |
| Observabilidade | TUI ANSI sempre ligado (`status_dashboard.ex`, 1.941 linhas): Agents n/max, Throughput tps + sparkline, Runtime, Tokens, Rate Limits, tabela Running (ID, STAGE, PID, AGE/TURN, TOKENS, SESSION, EVENT), Backoff queue. Web opcional (`--port`): Phoenix LiveView com cards Running/Retrying/Blocked/Tokens/Runtime e três tabelas; API JSON `GET /api/v1/state`, `GET /api/v1/<issue>`, `POST /api/v1/refresh`; sem autenticação, host `127.0.0.1` | `router.ex:17-41`, `presenter.ex`, `dashboard_live.ex:42-328` |
| Persistência | **nenhuma**: sem Repo, DB, ETS ou DETS; log único rotativo `log/symphony.log` (10 MiB × 5) correlacionado por `issue_id`/`session_id` | `log_file.ex:9-11`, `elixir/docs/logging.md` |
| Segurança | credenciais do tracker removidas do ambiente do Codex (`unset` + `env: false`); tools executadas host-side; cwd e symlinks validados; hooks são "fully trusted configuration" | `app_server.ex:192-228`, `SPEC.md` §15 |

Cada adapter expõe **uma** tool genérica ao agente, um passthrough autenticado da API bruta: "the tool can access whatever the configured Linear token can access" e "adds no idempotency key, retry, scope guard, or rate-limit policy" (`elixir/README.md:229-235`). A proteção é a credencial, não o Symphony.

### 1.6 O que é configurável

Tudo vive no front matter YAML do `WORKFLOW.md`, tipado por `elixir/lib/symphony_elixir/config/schema.ex`. Chaves e defaults (seleção; a tabela completa está nas notas):

| Bloco | Chave | Default |
|---|---|---|
| `tracker` | `kind` (obrigatório), `endpoint`, `api_key` (`$VAR`), `project_slug`, `assignee`, `provider` (mapa do adapter), `required_labels`, `active_states`, `terminal_states` | Linear/memory: ativos `Todo, In Progress`; terminais `Closed, Cancelled, Canceled, Duplicate, Done` |
| `polling` | `interval_ms` | 30.000 |
| `workspace` | `root` (aceita `~` e `$VAR`) | `<tmp>/symphony_workspaces` |
| `worker` | `ssh_hosts`, `max_concurrent_agents_per_host` | `[]`, nil |
| `agent` | `max_concurrent_agents`, `max_turns`, `max_retry_backoff_ms`, `max_concurrent_agents_by_state` | 10, 20, 300.000, `{}` |
| `codex` | `command`, `approval_policy`, `thread_sandbox`, `turn_sandbox_policy`, `turn_timeout_ms`, `read_timeout_ms`, `stall_timeout_ms` | `codex app-server`, mapa `reject`, `workspace-write`, `workspaceWrite` sem rede, 3.600.000, 5.000, 300.000 |
| `hooks` | `after_create`, `before_run`, `after_run`, `before_remove`, `timeout_ms` | nil, 60.000 |
| `observability` | `dashboard_enabled`, `refresh_ms`, `render_interval_ms` | true, 1.000, 16 |
| `server` | `port`, `host` | nil (desligado), `127.0.0.1` |

O corpo do arquivo é o prompt (Liquid, estrito) com `{{ issue.* }}` e `{{ attempt }}`. Reload a quente a cada 1 s. O `WORKFLOW.md` de referência da OpenAI (`elixir/WORKFLOW.md`) aponta para o projeto Linear `symphony-0c79b11b75ea`, clona `openai/symphony` no `after_create`, roda `gpt-5.5` com `model_reasoning_effort=xhigh`, `approval_policy: never`, `networkAccess: true`, 10 agentes e 20 turnos.

### 1.7 Instalação e operação

- Fonte: `mise trust && mise install` → `mix setup` → `mix build` (escript `bin/symphony`) → `./bin/symphony ./WORKFLOW.md` (`elixir/README.md:67-75`).
- Binário: Burrito por plataforma, publicado em tags `v*` e no prerelease rolante `nightly` (só em push para `main`, sem rebuild agendado); `chmod +x` e rodar; "still expect `codex`, `git`, and the selected tracker credentials on the target machine" (`elixir/README.md:79-104`; `.github/workflows/burrito-*.yml`).
- CLI: `symphony [--logs-root] [--port] [WORKFLOW.md]` + flag obrigatório de reconhecimento, não documentado no README.
- Processo único em foreground por `WORKFLOW.md` (um tracker, um projeto, um repo); sem Dockerfile do serviço, sem systemd/launchd. Escala horizontal só por `worker.ssh_hosts` (o orquestrador continua único; `ssh.ex` chama o `ssh` do sistema).
- Operação dogfood da OpenAI: skills `commit`, `push` (`gh pr create` com corpo validado por `mix pr_body.check`), `pull` (merge com `rerere`), `land` (loop até merge, revisões "## Codex Review — <persona>" vindas de GitHub Actions, respostas prefixadas `[codex]`, `gh pr merge --squash`, "Do not enable auto-merge"), `linear`, `debug` (rg no log), `release`. Esse workflow de Actions e as skills `github-pr-media`/`launch-app` citadas em `elixir/WORKFLOW.md:218` **não estão no clone** (não verificado).

## 2. Saúde do projeto (dados de 2026-11-06)

### 2.1 Números verificados

| Métrica | Valor | Como |
|---|---|---|
| Criação do repositório | 2026-02-26 | `gh api repos/openai/symphony --jq .created_at` |
| Primeiro commit público | `fa75ec6`, 2026-03-04 (um squash: os PRs #1–#24 são de 2026-02-26..03-03) | `git log --reverse` |
| Último commit / push | `be10a1b`, 2026-09-15 (52 dias atrás) | `git log -1`; `--jq .pushed_at` |
| Commits totais | 47 | `git rev-list --count HEAD` |
| Commits por mês | 03: 10 · 04: 2 · 05: 7 · 06: 4 · 07: 20 · 08: 1 · 09: 3 · 10: 0 · 11: 0 | `git log --date=format:%Y-%m` |
| Últimos 3 meses (08-06..11-06) | 4 commits, 1 autor | `git log --since --format=%an` |
| Últimos 6 meses | 35 commits, 7 autores | idem |
| Autores | 9, todos OpenAI (7 e-mails `@openai.com`, 2 com `company: OpenAI`); 5 com mais de um commit | `git shortlog -sne`; `gh api users/<login>` |
| Fator ônibus | Alex Kotliarskyi: 34/47 commits (72 %), 91,7 % das linhas, 55/64 merges | `git log --author --shortstat` |
| Commits com `Co-authored-by: Codex` | 10 | `git log --format=%b` |
| Issues | **desativadas** (`has_issues=false`; wiki e projects também) | `gh api ... --jq .has_issues` |
| Discussões | 51; 38 com zero comentários; 16 comentários no total, todos de contas sem vínculo; **0 respostas de qualquer login OpenAI** | GraphQL `discussions(first:100)` |
| PRs | 81: 64 merged, 17 closed, 0 open | `gh pr list --state all` |
| PRs por associação | COLLABORATOR 51 merged / 4 closed; CONTRIBUTOR 12/6 (todos logins `-oai`/`-openai`); NONE **0 merged / 7 closed** | GraphQL `authorAssociation` |
| PRs de fork | 1 (#50, funcionário OpenAI) | `--json isCrossRepository` |
| Mediana até merge | 0,36 h (p25 0,11; p75 2,34; máx 669 h) | `--json createdAt,mergedAt` |
| Mediana até fechar sem merge | 717,9 h (~30 dias; máx 4.576 h) | idem |
| Último sinal do mantenedor | 2026-10-21: 8 PRs antigos fechados em lote em 6 segundos, sem mensagem | GraphQL `timelineItems` |
| Releases | v0.0.1 2026-07-18 · v0.0.2 2026-07-24 · v0.0.3 2026-09-15 · `nightly` 2026-09-15; 8 assets cada (4 binários + sha256) | `gh api .../releases` |
| Downloads de binários | 478 / 2.335 / 3.185 / 226 (total 6.224) | `.assets[].download_count` |
| CI | 4 workflows ativos; último run verde 2026-09-15; runs por mês 07: 118 · 08: 9 · 09: 16 · 10: 0 · 11: 0 | `gh run list` |
| Branch `main` protegido | não | `--jq .protected` |
| Governança | **ausentes**: CODEOWNERS, SECURITY.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md, CHANGELOG, ROADMAP; presentes: LICENSE (Apache-2.0), NOTICE, PR template, `elixir/AGENTS.md` | `test -e` |
| Stars / forks / watchers | 27.958 / 2.891 / 175; ainda cresce (5 eventos em 2026-11-06); forks recentes ~80–105/mês | `gh api repos/openai/symphony` |
| Forks mais ativos | `JJLiebig/sympp` (936 commits à frente, push 2026-11-06, 5★), `sandsower/rondo` (409 à frente, 28★), `odysseus0/symphony` (82★, 5 à frente) — nenhum com massa crítica | `gh api .../forks?sort=stargazers` |
| Cobertura de testes | threshold 100 % **com 28 módulos ignorados** (Orchestrator, AgentRunner, AppServer, Workspace, todos os clients e a web) | `elixir/mix.exs:11-46` |

### 2.2 Leitura dos dados

- **Cadência:** o pico de julho (20 commits) é o trabalho de adapters e Burrito para `v0.0.1`/`v0.0.2`; desde agosto são 4 commits, os três últimos em 2026-09-15 para fechar a `v0.0.3`. Nenhum commit em outubro ou novembro.
- **Mantenedores ativos:** um. Alex Kotliarskyi assina 72 % dos commits, 92 % das linhas e 55 dos 64 merges; nos últimos 3 meses só ele commitou.
- **Intake de bugs:** inexistente. Issues desativadas; discussões sem nenhuma resposta de mantenedor. Relatos com correção pronta ficaram sem resposta: #107 (três achados de segurança, 2026-07-19), #126 (app-server pendurado após cancelamento), #131 (rate limits camelCase do Codex 0.160), #133 (turnos falhos tratados como completos), #134 (**`v0.0.3` falha o `thread/start` com Codex 0.164/0.165**, 2026-10-26). A mediana de resposta de mantenedor não é calculável: o conjunto é vazio.
- **Contribuição externa:** não acontece. Os 7 PRs de autores sem vínculo foram fechados sem merge e sem comentário de mantenedor; 80 dos 81 PRs vieram de branches do próprio repositório.
- **Releases e CI:** a parte mais "produto" do repositório — binários para quatro plataformas, sha256, smoke test em quatro runners — é automação em volta de um projeto interno, não compromisso de suporte. O `nightly` só roda em push, então está parado desde 2026-09-15 e é idêntico ao `v0.0.3`.
- **Licença e dependências:** Apache-2.0; stack moderna (Phoenix 1.8, LiveView 1.1, OTP 28) que ninguém está acompanhando; sem SECURITY.md para reportar CVEs.
- **Origem:** os PRs internos levam chaves Linear `MT-703`/`MT-718`, e o texto reproduzido do anúncio da OpenAI diz que o Symphony nasceu "while working on an internal productivity tool". A página oficial (`https://openai.com/index/open-source-codex-orchestration-symphony/`) devolveu HTTP 403 e **não foi lida**; fontes secundárias datam o post em 2026-04-28 (sete semanas depois de o repositório abrir, em 2026-03-04) e parafraseiam que a OpenAI "does not plan to maintain Symphony as a standalone product" e que "some teams at OpenAI saw a 500% increase in landed pull requests" — **não verificado na fonte**.

### 2.3 Classificação

Numa escala de 0 (experimento abandonado) a 10 (produto com SLA), os dados colocam o Symphony perto de **3**: pesquisa/experimento publicado como referência, com boa automação de release, sem canal de suporte, sem comunidade atendida e dependente de um engenheiro continuar interessado. O valor durável está no `SPEC.md`, a parte que o próprio README pede para reimplementar.

## 3. Comparação ponto a ponto

"Nosso" = `dsh-superagent` (orquestrador + executor no DeepSeek Harness; nós não alteramos o código, só prompts e settings via API em `127.0.0.1:3082`) + `agent-board` (este repositório, só leitor do agente).

| Capacidade | Symphony | Nosso | Diferença que importa |
|---|---|---|---|
| **Como o trabalho entra** | Estado da issue no tracker (`active_states`, `required_labels`, assignee), polling de 30 s (5 s na OpenAI); mover o card dispara | Menção `@sallaumen-agent` por alguém da lista, lida por polling de notificações a cada 60 s (`dsh: src/sources/github-trigger.ts:60-87`, `src/sources/github.ts:25`); o board cria a issue com a menção no corpo (`lib/agent_board/board.ex:252-280`); editar a issue não dispara | No Symphony o tracker é o plano de controle; no nosso é a frase. Na prática o board já faz o papel de plano de controle ao abrir a issue com a menção. Latência de entrada maior no nosso (60 s). |
| **Trackers** | Linear, GitHub Issues, GitLab, Jira, Asana (mais `memory`) | GitHub.com (sem GHES, sem GitHub App) e Feishu desligado (`dsh: docs/006-deployment.md`) | Irrelevante hoje: operamos um repositório no GitHub. |
| **Agente / modelo** | **Só Codex** (`codex app-server`); modelo por flag do Codex (`gpt-5.5`, `xhigh`) | Modelo por papel (`eval.model`, `executor.model`) resolvido pelo DSH; hoje DeepSeek (`dsh: src/policy.ts:70-96`; `docs/agent/setup.md` §3) | **O bloqueio da migração.** Symphony exige Codex/OpenAI; trocar o agente é reescrever `Codex.AppServer`. |
| **Ciclo de vida interno** | `Unclaimed → Claimed → Running → RetryQueued → Released` (SPEC §7); fases de tentativa; estado do tracker é a verdade | Decision `accept|stop|ignore|unavailable`; Assignment `pending|running|ended`; Report `progress|waiting|ready|blocked|failed|dropped`; outcome `completed|merged|closed|dropped|stopped` (`dsh: src/core/model.ts:211-285`); board `queued running question ready blocked done closed stopped archived` (`lib/agent_board/board/task.ex:10`) | O nosso modelo é mais rico (relatórios, outcomes), mas o board deriva `question`/`ready` por heurística textual ("?" no resumo) (`lib/agent_board/sync.ex`, commit `0405c41`). |
| **Isolamento** | Workspace por issue sob `workspace.root`, chave sanitizada, hooks, validação de symlink; reutilizado entre runs | Worktree por ticket criado pelo *prepare command* (`git worktree add -b agent/<nome>`), 10 min, sob `~/.dsh/state/superagent/work/` (`dsh: src/executor/dsh.ts:28,57`; `docs/agent/how-it-works.md`) | Equivalentes. Nenhum dos dois é fronteira de segurança (`danger-full-access` no nosso; `approval_policy: never` + rede no deles). |
| **Limpeza** | Estado terminal → worker morto e workspace apagado; sweep no startup; hook `before_remove` fecha PRs órfãos (`workspace.before_remove.ex`) | Nenhuma: "Nothing deletes old records yet, so these grow without bound" (`dsh: docs/007-architecture.md`); worktrees ficam | **Lacuna nossa.** Fácil de fechar com um script. |
| **Concorrência** | `max_concurrent_agents` 10, teto por estado, teto por host SSH, hosts remotos | `executor.maxWorkers` default 3 (1..16) + 1 slot para mensagem humana (`dsh: src/policy.ts:93`); hoje rodamos com um worker por decisão do Lucas, para medir vazão antes de paralelizar (valor vivo fora dos repositórios: não verificado) | Quando paralelizarmos, o teto por estado e por host do Symphony são boas referências; o DSH já tem o knob. |
| **Gates** | Nenhum pelo host; `before_run` poderia rodar um, mas o fluxo de referência confia no prompt ("checks verdes" antes de `Human Review`) | Nenhum pelo host; a política exige `mix precommit` no head e auto-relato; o board **infere** `CI local ok/falhou/?` do texto do relatório (`lib/agent_board/local_ci.ex:497-608`) | Mesma fraqueza. O Symphony tem um seam (`before_run`/`after_run`) que o DSH não tem. |
| **Política e prompts** | `WORKFLOW.md` **versionado no repositório**, front matter + prompt Liquid, reload a quente, validado no boot | Três seções (Communication, Ticket scope, Delivery requirements) salvas por `PUT /orchestrator/api/prompts` com `baseRevision`, versões imutáveis, **fora do git** (`dsh: docs/004-prompts.md`; `docs/agent/setup.md` §8) | **Ideia nº 1.** Nossa política está num SQLite, sem diff nem revisão; o texto literal ativo nem é verificável neste repositório. |
| **Entrega e merge** | Agente abre PR (`gh`), move para `Human Review` (estado de handoff fora dos ativos); humano move para `Merging`; agente faz squash-merge pela skill `land` | Agente abre PR e, desde 2026-11-07 UTC, mescla o próprio PR com `gh pr merge --merge --match-head-commit <sha>` quando `mix precommit` passou, nenhuma revisão pede mudanças e `mergeable == MERGEABLE`; sem branch protection; "GitHub Actions is never a reason to wait" (`docs/agent/setup.md` §8, commit `bd4ffd1`) | O Symphony implementa o gate humano **por exclusão de um estado dos `active_states`**, sem código. Nós escolhemos não ter gate; se um dia quisermos, uma label de handoff dá o mesmo efeito. |
| **Humano no loop** | Mapa `blocked` em memória quando o Codex pede aprovação/input; comentário único `## Codex Workpad` (Plan, Acceptance Criteria, Validation, Notes, Confusions); **nenhuma notificação** | Report `waiting` + `human_action`; estágio `person/*`; board "Precisa de você" (`blocked ++ review ++ question`, `lib/agent_board/work.ex:648-673`) e **voz** (`lib/agent_board/announcer.ex`, commit `87511a9`) | Estamos à frente em chamar o dono. O workpad deles é melhor para **ler** o estado: uma estrutura fixa, não "?" no texto. **Ideia nº 2.** |
| **Retries, stall, timeouts** | Continuação 1 s; backoff 10 s·2ⁿ ≤ 5 min sem teto; stall 5 min sem evento → mata e reagenda; silêncio 1 h por turno; `max_turns` 20; reconciliação a cada tick (issue fechada no meio → para) | Launch 3 tentativas transitórias (5 s→300 s); turno 15/30/60 s; `failed` **não** é retentado sozinho — espera Retry humano (`dsh: docs/003-execution.md`); sem detecção de stall por evento; board tem frescor `agent_running_ttl` 2 min (`lib/agent_board/sync/freshness.ex`) | O Symphony se recupera sozinho de falhas transitórias e de workers travados; o nosso para e espera. **Ideia nº 5** (stall visível no board). |
| **Tokens e custo** | Por issue e global (in/out/total), runtime, rate limits — em memória, no TUI e na API | Executor: **nada** por ticket (`dsh: docs/007-architecture.md`); board: `ai_calls` com tokens, `cost_micros`, teto diário 5 M, só para as chamadas do próprio board (`lib/agent_board/ai/call.ex`) | **Lacuna nossa.** Não sabemos quanto custa um ticket. Depende de o DSH expor uso (investigar). |
| **Observabilidade** | TUI + LiveView + JSON: running/retrying/blocked, tokens, turnos, último evento humanizado, fila de backoff; **sem histórico** | Painel do DSH (Overview, Source, Trigger, Eval, Execution, Settings); board com lanes, "passo real" lido do worktree (`lib/agent_board/agent_worktree.ex`), frescor, `events`, LiveDashboard, API sem auth; `status.sh`/`tickets.sh`/`counts.sh`/`logs.sh` | Eles têm telemetria por run melhor (tokens, turno, último evento); nós temos histórico, frescor e contexto de GitHub. |
| **Persistência** | Nenhuma; reinício perde retries e bloqueios | SQLite do agente (fonte) + Postgres do board (`repositories, tasks, pull_requests, reviews, events, comments, ai_calls, settings`) | Vantagem nossa decisiva para métricas e auditoria. |
| **Métricas** | Throughput em tokens/s + sparkline; runtime; nada de PRs ou vazão | `MergeTrend` 7 d, `Work.merge_log`, digest desde a última visita, `flow` 24 h do DSH; painel por hora em construção na sessão irmã; **ninguém calcula tempo de ciclo** | Nenhum dos dois mede vazão por hora nem ciclo por ticket; os dados para isso existem só no nosso lado (`assignments[].startedAt`, `pull_requests.merged_at`, `tasks.started_at/state_changed_at`). |
| **Spec e testes** | `SPEC.md` normativo (18 seções, pseudocódigo, matriz de testes, checklist de conformidade); 15 k linhas de ExUnit sobre OTP real com app-server falso | `docs/maintainer-contract.md` vinculante, ADRs, `PIPELINES.md`, Elixir Agent Kit; DSH com 9 docs numerados e 59 specs; board com 46 arquivos de teste | O SPEC é a melhor peça do Symphony: serve de **checklist** para auditar o nosso ciclo (reconciliação, restart, dispatch obsoleto). **Ideia nº 3.** |
| **Segredos** | Tokens do tracker fora do ambiente do filho; tools host-side | `GH_TOKEN`/`GITHUB_TOKEN` removidos; shim `gh` em `worker-bin`; credential helper do agente (`dsh: docs/006-deployment.md`) | Equivalentes. |
| **Empacotamento e serviço** | Escript ou binário Burrito em foreground; sem serviço | DSH em tmux (`scripts/dsh-superagent`), board em launchd na 4099 (`ops/com.agentboard.plist`) | Nada a trazer. |
| **Saúde do projeto** | 1 mantenedor, 52 dias parado, sem intake, autodeclarado protótipo | Nós: commits diários; DSH: protótipo de pesquisa "not production-ready" (`dsh: README.md`), um commit no nosso clone | Ambos protótipos; o nosso está vivo e sob nosso controle. |

## 4. Recomendação

### 4.1 Migrar?

**Não.**

- **Custo:** trocar DeepSeek por Codex (assinatura/API OpenAI e dependência da versão do CLI, que a `v0.0.3` já não acompanha segundo #134); reescrever a leitura do board (hoje SQLite do agente; no Symphony só haveria `GET /api/v1/state` em memória); reproduzir a entrada por menção (o Symphony lê estado de issue, não comentários); re-escrever a política de merge como `WORKFLOW.md`; abandonar `tickets.sh`/`counts.sh`/`status.sh`.
- **O que perderíamos:** histórico persistente (SQLite + Postgres), o modelo de relatórios (`waiting`/`ready`/`blocked`/`human_action`) de que "Precisa de você" e a voz dependem, Retry humano com reuso de branch e PR, o Eval com lista de permitidos, a independência de provedor, e a possibilidade de o Lucas editar a política pela API sem reiniciar.
- **O que ganharíamos:** paralelismo com tetos por estado e por host, workers SSH, reconciliação robusta (issue fechada no meio do run para o agente), retries e stall automáticos, tokens e rate limits por run, `WORKFLOW.md` a quente, cinco trackers.
- **Risco de abandono:** alto. Um mantenedor, zero respostas públicas, autodeclaração de protótipo e recomendação explícita de "implemente a sua própria versão endurecida".

### 4.2 Adotar peças

Sim, as de desenho. Nenhuma exige código do Symphony; todas cabem em prompts, scripts e no board:

1. Política e prompt como arquivo versionado neste repositório, com um script que faz `get`, `diff` e `put` contra a API do orquestrador (o que o `WORKFLOW.md` + reload a quente dão a eles).
2. "Workpad": um comentário estruturado por issue, com seções fixas, que o board lê em vez de adivinhar por "?".
3. `SPEC.md` §7, §8 e §14 como checklist para auditar o ciclo de vida do DSH e registrar o resultado no contrato.
4. Limpeza em estado terminal: remover worktrees de tickets encerrados e fechar PRs órfãos (equivalente ao `before_remove`).
5. Stall e telemetria por run no card: "sem sinal há N min", turnos, e, se o DSH expuser, tokens.

### 4.3 Só aprender

Já feito com este documento: o modelo de "estado de handoff fora dos `active_states`" como gate humano sem código; a ordenação prioridade → idade → identificador; a revalidação por id antes de despachar; a contabilidade de tokens por totais absolutos (nunca por deltas reportados); a separação leitura (orquestrador) × escrita (agente via tool com credencial host-side).

### 4.4 Ideias para trazer, por prioridade

Esforço: **P** ≤ meio dia · **M** 1–2 dias · **G** > 2 dias. Valor: o que muda para o Lucas operando a plataforma.

| # | Ideia | No Symphony | Onde entraria aqui | Esforço | Valor |
|---|---|---|---|---|---|
| 1 | **Política versionada em arquivo + sync com a API** | `WORKFLOW.md` no repo, validado no boot, reload a quente (`workflow_store.ex`) | `docs/agent/prompts/{communication,scope,delivery}.md` + `scripts/agent/prompts.sh get|diff|put` usando `GET/PUT /orchestrator/api/prompts` com `baseRevision`; `docs/agent/setup.md` §8 passa a apontar para o arquivo | M | Alto: a política de merge vira texto revisável em PR; some o "não verificado" sobre o texto ativo; o classificador que bloqueou o `PUT` deixa de ser problema (script com corpo em arquivo). |
| 2 | **Workpad: um comentário estruturado por issue** | `## Codex Workpad` com Plan / Acceptance Criteria / Validation / Notes / Confusions, editado in place (`elixir/WORKFLOW.md:295-329`) | Seção Communication do prompt (via ideia 1) + parser no board (`lib/agent_board/board.ex` `agent_asked?`, `lib/agent_board/local_ci.ex`) lendo seções fixas: Pergunta, Validação (`mix precommit` + sha), Bloqueio | M | Alto: menos ruído de comentários; `question`/`blocked`/`CI local` passam a ser lidos de campos, não de "?" e frases. |
| 3 | **Auditoria do ciclo de vida contra o SPEC** | `SPEC.md` §7 (estados), §8 (tick, reconciliação, dispatch obsoleto), §14 (falhas, restart), §18 (checklist) | ADR `docs/decisions/0003-ciclo-de-vida-do-agente.md`: o que o DSH faz quando a issue é fechada durante o run, quando reinicia com ticket `running`, quando a menção chega duas vezes; o que o board deve mostrar em cada caso | M | Alto: hoje ninguém sabe responder essas três perguntas; é o que mais vai doer ao paralelizar. |
| 4 | **Limpeza de worktrees e PRs órfãos** | Terminal → `rm -rf` do workspace; sweep no startup; `mix workspace.before_remove` fecha PRs sem merge | `scripts/agent/cleanup.sh`: lista tickets `ended` no SQLite, `git worktree remove` + `prune`, fecha PRs abertos de branches `agent/*` cujo ticket terminou sem merge; `--dry-run` por padrão | P/M | Médio: disco e lista de PRs limpos; evita branch stale ser retomada por engano. |
| 5 | **Stall visível no card** | `stall_timeout_ms` 5 min sem evento → reinicia; TUI mostra AGE/TURN e último evento | Board: "sem sinal há N min" a partir de `report.at`/`idleAt` no SQLite e mtime do worktree; acima de um limiar vira item de "Precisa de você" com ação Retry/Stop (`lib/agent_board/work.ex`, `lib/agent_board/sync/freshness.ex`) | M | Médio/alto com um worker só: um ticket travado hoje trava a fila inteira em silêncio. |
| 6 | **Tokens e custo por ticket** | `codex_totals` por issue (`orchestrator.ex:1725-1797`), rate limits | Spike: descobrir se o DSH grava uso por Session (logs em `.artifacts/`, health `models`); se sim, coluna no card e soma no `ai_calls`-like | P (spike) → G | Alto se possível; hoje o custo do executor é invisível. |
| 7 | **Ordenação e revalidação de dispatch** | prioridade → `created_at` → id; refetch por id antes de lançar | Quando `maxWorkers` > 1: pedir ao DSH (settings/prompt) ordem por idade; o board já mostra a Fila em ordem — documentar a regra | P | Baixo agora, médio ao paralelizar. |
| 8 | **Estado de handoff opcional** | `Human Review` fora dos `active_states` = gate humano sem código | Label `needs-owner` que a política respeita (não mesclar) e o board mostra em "Precisa de você" | P | Baixo: o Lucas decidiu não revisar; fica como opção para tickets sensíveis. |
| 9 | **Endpoint JSON por tarefa** | `GET /api/v1/<issue>` com workspace, tentativas, último erro | `GET /api/tasks/:id` no board com worktree, relatório, gate local, PR | P | Baixo: conveniência para scripts. |

## 5. Plano da próxima frente paralela

Cinco pontos, cada um do tamanho de uma issue/PR, independentes entre si e da sessão irmã (métricas por hora). Nenhum altera o `dsh-superagent`; dois alteram prompts pela API, três alteram este repositório.

1. **Política versionada e script de sync (ideia 1).** Criar `docs/agent/prompts/` com as três seções e `scripts/agent/prompts.sh` (`get` grava os arquivos; `diff` compara com a API; `put` envia com `baseRevision` lido do `get`). Atualizar `docs/agent/setup.md` §8 e a tabela de scripts no `AGENTS.md`. Pronto quando `prompts.sh diff` sai limpo contra a revisão ativa e o texto literal da Delivery requirements está em git. Gate: `mix format --check-formatted` e `shellcheck` nos scripts.
2. **Workpad no prompt e no board (ideia 2).** PR A (prompt, via `prompts.sh put`): a seção Communication pede um comentário único `## Relatório do agente` com `### Plano`, `### Validação` (comando, resultado, sha), `### Pergunta` (vazio ou uma pergunta), `### Bloqueio`. PR B (board): `AgentBoard.Workpad.parse/1` + `Board.agent_asked?` e `LocalCI` passando a preferir o workpad quando existe, com fallback para a heurística atual; testes com fixtures dos dois formatos. Pronto quando um ticket com workpad aparece como `question` sem "?" no resumo e o `CI local` vem do campo Validação.
3. **ADR do ciclo de vida (ideia 3).** Ler `dsh: src/core/tickets.ts`, `src/executor/dsh.ts` e `src/sources/github.ts` com o SPEC §7/§8/§14 ao lado e responder, com citação: issue fechada no GitHub durante o run; reinício do DSH com Assignment `running`; segunda menção na mesma issue; PR fechado sem merge. Registrar em `docs/decisions/0003-ciclo-de-vida-do-agente.md` o comportamento observado, o que o board mostra hoje e o que deveria mostrar. Pronto quando cada pergunta tem resposta citada ou "não verificado" com o experimento que falta.
4. **Limpeza de worktrees e PRs órfãos (ideia 4).** `scripts/agent/cleanup.sh` com `--dry-run` por padrão, `--apply` para executar; lê tickets `ended` no SQLite (mesma consulta de `tickets.sh`), remove o worktree correspondente em `~/.dsh/state/superagent/work/`, roda `git worktree prune`, e fecha com comentário os PRs abertos de branch `agent/<nome>` cujo outcome é `closed|dropped|stopped`. Linha no `AGENTS.md` e em `docs/agent/how-it-works.md`. Pronto quando o `--dry-run` lista exatamente o que `tickets.sh` mostra como encerrado e nada mais.
5. **Stall visível (ideia 5).** No board, calcular `last_signal_at` por ticket `running` = max(`report.at`, `idleAt`, mtime do worktree) e expor `stalled_for` no card; acima de `:stall_after_ms` (default 15 min) o ticket entra em "Precisa de você" com `why` "Sem sinal há N min" e ações Retry (API do DSH) / Stop. Contrato em `docs/maintainer-contract.md` (é derivado, nunca escrito no SQLite; uma frase por mudança de estado na voz). Pronto quando um ticket travado aparece em até um ciclo do poller (10 s) depois do limiar. Coordenar com a sessão de métricas para não duplicar `last_signal_at`.

Achado lateral da pesquisa, para uma issue à parte: `scripts/agent/tickets.sh` e `counts.sh` leem `assignments[0]` (a primeira Assignment), enquanto `AgentBoard.AgentState.normalize/1` usa a última; depois de um Retry os scripts mostram o relatório antigo (`lib/agent_board/agent_state.ex:191-231`).

## 6. Não verificado

- Texto e data do anúncio oficial da OpenAI (HTTP 403); as frases "500 % de PRs" e "não pretende manter como produto" são paráfrases de terceiros.
- Linha do tempo de stars (endpoint `stargazers` com `star+json` devolveu 404/401); o pico foi estimado por forks e discussões (100 forks em 48 h a partir de 2026-03-04).
- Colaboradores com push (403) e afiliação de 6 dos 9 autores (só e-mail de commit e convenção de login).
- Versões do Codex CLI compatíveis com a `v0.0.3`; o relato de incompatibilidade (#134) não foi reproduzido.
- Se os testes do Symphony passam: nada do clone foi executado.
- O workflow de Actions que gera "## Codex Review — <persona>" e as skills `github-pr-media`/`launch-app` citadas no `WORKFLOW.md` não estão no clone.
- Do nosso lado: o texto literal da Delivery requirements ativa no orquestrador, o valor vivo de `executor.maxWorkers` e do modelo por papel, e o `executor.prepare` da nossa instalação vivem fora dos dois repositórios.
- Se o DSH registra tokens por Session em algum lugar (base da ideia 6).

## 7. Como reproduzir

```sh
# clone de leitura, em diretório próprio; não execute nada dele
git clone https://github.com/openai/symphony /caminho/isolado/symphony
C=/caminho/isolado/symphony
git -C $C log --format='%ad' --date=format:%Y-%m | sort | uniq -c
git -C $C shortlog -sne HEAD
git -C $C log --since=2026-08-06 --format='%an' | sort | uniq -c
gh api repos/openai/symphony --jq '{created_at,pushed_at,stargazers_count,forks_count,has_issues,license:.license.spdx_id}'
gh pr list --repo openai/symphony --state all --limit 500 --json state --jq '.[].state' | sort | uniq -c
gh api graphql -f query='{repository(owner:"openai",name:"symphony"){discussions(first:100){totalCount nodes{number comments{totalCount}}}}}'
gh run list --repo openai/symphony --limit 100 --json name,conclusion,createdAt
gh api repos/openai/symphony/releases --jq '.[] | "\(.tag_name) \(.published_at) \([.assets[]|.download_count]|add)"'
```

As notas de pesquisa trazem os 51 números com o comando exato de cada um, a tabela completa do schema de configuração e o inventário citado da nossa plataforma.
