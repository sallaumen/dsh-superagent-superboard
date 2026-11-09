# Alfred × a nossa plataforma: plano de produto

- **Data da análise:** 2026-11-07.
- **Objeto:** a especificação "Alfred" (versão 1.2, outubro de 2026), que um colega escreveu para que uma IA construa, fase a fase, um assistente pessoal no computador da pessoa. É texto de terceiros: lemos uma cópia local fora do repositório; aqui só há paráfrase e trechos curtos entre aspas.
- **Nossa plataforma:** o board (este repositório), o executor `dsh-superagent` (DeepSeek Harness, prefixo `dsh:` nas citações, raiz em `/Users/tavano/Documents/deepseek-harness/default-workspace/dsh-superagent-prototype`) e o uso direto de Claude Code e Codex fora do board.
- **Objetivo do dono:** um dia trabalhar só criando tarefas no board, sem abrir DeepSeek, Claude ou Codex, com o board decidindo para onde cada tarefa vai.
- **Método:** leitura do board e do protótipo com citação de arquivo e linha; spikes só de leitura nos arquivos locais de uso das três ferramentas (estrutura e números, nunca o conteúdo das conversas); `--help` das CLIs. Nenhuma chamada paga foi feita. Workflow do Elixir Agent Kit: `ai-orchestration` (o risco é atribuir trabalho e custo ao executor certo), em modo de análise: este PR só traz documentação.
- **Fora do plano:** o canal no Telegram. O dono decidiu em 2026-11-07 deixá-lo para depois; a seção 5 diz o que isso adia.
- **Notas de pesquisa** (comandos e saídas dos spikes): pasta de notas da sessão, `alfred-usage-spike.md` e `alfred-dsh-api.md`. Este documento é o destilado.

## Resumo

**Não adotar o Alfred como base. Trazer seis ideias dele e seguir um caminho em quatro passos até o objetivo do dono: o board vê as três ferramentas, sugere para onde cada tarefa vai, despacha, e só então decide sozinho, por categoria, onde já provou acertar.**

Três fatos decidem:

1. **A maior parte do trabalho está fora do board.** Nos últimos 7 dias houve 120 sessões do Claude Code em 11 repositórios e 44 threads do Codex em 5; o executor do board fez 33 tickets no total, todos no único repositório que o orquestrador vigia (`sallaumen/arena-rogue`). O board mostra dois repositórios e um executor.
2. **O DSH não roteia por tarefa.** O modelo é global por papel e o executor é fixo no runtime (`dsh:src/policy.ts:91-97`, `dsh:src/app/runtime.ts:68`); a API do orquestrador não cria ticket. A decisão de rota tem de ficar no board, antes do executor.
3. **As três ferramentas deixam o uso legível em arquivos locais, sem chamada paga, mas em moedas diferentes.** O DeepSeek gasta saldo de conta (US$ estimado pela tabela do board), o Claude Code roda na assinatura Max (o US$ que ele calcula é preço de lista, não fatura) e o Codex no plano ChatGPT (só há o percentual da cota semanal). A visualização e o roteador mostram cada um na sua moeda e nunca somam as três.

As ideias do Alfred que entram: o **portão de risco no código**, com uma confirmação que diz os valores reais (F2.3); a **escada de confiança**, aqui aplicada à escolha do executor: sugerir, confirmar, automático por categoria depois de 10 acertos, nunca subindo sozinho (F2.4, F4.1); o **custo visível em cada escolha** (F1.5, F2.4); o **resumo do dia com relógio de parede** (F1.6); os **fatos aprovados** como memória de preferências (F4.2); e a **delegação ao Claude Code como ação confirmada**, com o board dono da decisão de risco (F3.0–F3.3). O resto do Alfred (motor próprio, canais, automações que o assistente escreve para si, controle da tela) não entra; a seção 5 diz por quê.

**As três primeiras frentes**, que podem abrir hoje em paralelo:

1. **Ver Claude Code e Codex** (F1.1 e F1.2, depois F1.3): leitores de uso só de leitura e o livro de uso. Não precisa de nada do dono.
2. **Registro de ações com risco** (F2.3): o portão único, pré-requisito de qualquer despacho que gasta. Não precisa de nada do dono.
3. **ADR 0004 da fronteira de despacho** (F3.0): escrever a decisão e colher do dono D1, D2, D3 e D5 enquanto as duas primeiras andam.

## 1. O que o Alfred é

Não é software: é um briefing para uma IA instalar, com a chave de API da própria pessoa, um assistente local em Python (FastAPI, SQLite, cofre do sistema). O desenho tem cinco órgãos (ouvido, cérebro, mãos, memória, voz e tela) e uma regra: toda ação das mãos tem um risco, verde (só lê), amarelo (muda algo reversível) ou vermelho (apaga, envia para fora, gasta dinheiro), e "o código impõe isso, não o prompt". Em cima disso vêm quatro níveis de autonomia que só sobem depois de um portão, memória em três camadas, rotinas com relógio de parede, roteamento de modelo por tarefa com custo visível, transparência de cada chamada de ferramenta, objetivo em segundo plano, automações, conectores, supervisão de um trabalhador com relatório e auditoria, e a delegação de programação ao Claude Code como ação vermelha.

O que ele resolve é diferente do que resolvemos. O Alfred é um assistente geral para uma pessoa leiga; o nosso board é um painel de controle de agentes de código para um desenvolvedor, que já tem histórico em Postgres, GitHub como trilha e um executor autônomo que abre e mescla os próprios PRs. Por isso a comparação abaixo não pergunta "migrar?", e sim "que peça do Alfred falta para o board decidir e despachar sozinho?". A análise anterior do Alfred, feita para outro projeto do dono, chegou à mesma leitura: a base de segurança daquele projeto já estava à frente, e o valor do Alfred está na camada de confiança e aprendizado acima do portão.

## 2. Comparação ponto a ponto

Veredito: **trazer** (a ideia entra quase como está), **adaptar** (entra com outra forma) ou **não trazer**. O número entre colchetes aponta o item do plano (seção 4).

### 2.1 Gerenciamento de tarefas

| Tema | Alfred | Hoje no board e no agente | Veredito |
|---|---|---|---|
| **Objetivo em segundo plano** | Aceita um objetivo, quebra em passos, registra o progresso num arquivo, avisa ao terminar ou travar; passos amarelos e vermelhos esperam a pessoa | O composer refina o pedido e o divide em tarefas que fecham sozinhas (`lib/agent_board/intake.ex`, duas chamadas no tier rápido); cada tarefa vira uma issue com a menção ao agente (`lib/agent_board/board.ex:253`, `lib/agent_board_web/live/board_live.ex:2062`); o progresso de cada uma é o workpad (`## Relatório do agente`, `lib/agent_board/workpad.ex`); a tarefa nascida de outra guarda `origin_task_id` (`lib/agent_board/board/task.ex:25`). Não existe o objetivo como coisa: o board não sabe que cinco tarefas são um pedido só nem quando o pedido terminou | **Adaptar** [F3.4]: o objetivo é um grupo de tarefas com um critério de pronto, e o progresso é calculado das tarefas, nunca escrito à mão |
| **Fila** | Fila de comandos que sobrevive ao computador desligado | Fila do board (`Lanes.queue/3`, `lib/agent_board/lanes.ex`) e do runner (`load.queued`, `lib/agent_board/orchestrator.ex`) | **Não trazer**: já existe e é persistente nos dois lados |
| **Retomada** | Reiniciar não perde comando; no máximo três tentativas com espera crescente | Retentativa automática de falha transitória em 1, 5 e 15 min, uma por Assignment (`lib/agent_board/auto_retry.ex`, contrato "Automatic retry"); "Tentar de novo" e "Religar o agente" confirmados (`lib/agent_board/agent_control.ex`); o que o DSH faz ao reiniciar está no ADR 0003 | **Não trazer**: estamos à frente; a mesma regra vale para os executores novos [F3.5] |
| **Autonomia por níveis** | Quatro níveis (responde, faz quando pede, avisa e age no autorizado, orquestra) e modos trocáveis (observar, supervisionado, liberado); só sobe depois de um portão; após 10 acertos seguidos oferece tornar automático, nunca sobe sozinho | Implícita e espalhada: o executor mescla os próprios PRs por texto de prompt (`docs/agent/setup.md` §8); a retentativa automática liga e desliga por variável (`AGENT_BOARD_AUTO_RETRY`); a voz cria direto só quando o dono diz "cria direto" (contrato, "The voice"). Nenhuma tela diz em que nível cada coisa opera | **Trazer** como modo do roteador [F2.4, F4.1]: *sugerir* (o dono escolhe), *confirmar* (o board escolhe e o dono aprova), *automático* (por categoria, oferecido depois de N acertos, revogado no primeiro erro) |
| **Portão de risco no código** | Toda ferramenta declara risco; vermelho sempre confirma com os valores reais; a confirmação vem da pessoa, nunca do modelo; recusa registrada | As confirmações existem, mas por porta: o componente `AgentAction` não age no primeiro clique (`lib/agent_board_web/live/board_components/agent_action.ex:1-14`); a conversa por voz transforma escrita em proposta que só o "sim" falado executa (`lib/agent_board/conversation.ex:95-127`); o catálogo de comandos marca `local`, `read`, `confirm` e `direct` (`lib/agent_board/voice/commands.ex`). A API JSON cria, para e arquiva sem confirmação (`lib/agent_board_web/controllers/board_controller.ex:38-73`), aceitável hoje porque o serviço só escuta em `127.0.0.1:4099` (observado com `lsof`; `config/dev.exs:23`). Não há um catálogo único de ações com risco | **Trazer** [F2.3]: um registro de ações do board (criar, perguntar, parar, arquivar, tentar de novo, religar, mudar o teto, despachar para um executor pago) com risco, frase de confirmação com os valores reais e o registro da decisão; UI, voz e API passam por ele. Despachar para Claude ou Codex é amarelo ou vermelho porque gasta |
| **Teto de gasto** | Teto diário e por tarefa; timeout por tarefa | Teto diário de 5 M tokens só para as chamadas do próprio board (`lib/agent_board/ai/budget.ex:15`), checado antes da rede; teto diário de caracteres da ElevenLabs; nenhum teto sobre o executor | **Trazer** [F2.4, F3.3]: teto por tarefa e por dia em cada executor, visível antes do despacho |
| **Botão de parada** | "Para tudo" interrompe | "Parar" por tarefa fecha a issue (`Board.stop_task/2`, `lib/agent_board/board.ex:354`); não há pausa global do despacho | **Trazer** [F3.3]: "pausar despacho" para o roteador; o que já roda continua, nada novo sai |

### 2.2 Comunicação

| Tema | Alfred | Hoje | Veredito |
|---|---|---|---|
| **Fluidez e mensagens curtas** | Respostas curtas, em voz no máximo duas frases; repetir o que entendeu antes de algo vermelho; dizer "não tenho certeza" | A voz fala no máximo duas frases por atualização (`lib/agent_board/announcer.ex:25`), respostas grátis falam a primeira frase (`voice_replies` = `short`), toda frase vem de `AgentBoard.Voice.Phrases`, e a leitura por voz responde só com fatos do board (`lib/agent_board/conversation/lookup.ex`) | **Não trazer**: já é a regra |
| **Confirmação com os valores reais** | A frase de confirmação traz os valores ("apagar a pasta X"), não "confirma?" | `AgentAction` mostra o que vai acontecer; a proposta por voz nomeia a tarefa e a pergunta | **Adaptar** [F2.3, F2.4]: a confirmação de um despacho pago diz executor, repositório, teto e custo estimado ("Mandar #412 para o Claude Code no arena-rogue, teto US$ 3, estimativa US$ 0,80?") |
| **Relatórios** | Relatório diário do que o trabalhador fez; revisão semanal de 10 minutos; "o que você fez hoje?" lido de um log só de acréscimo | Digest de uma frase desde a última visita (`Lanes.digest/3`, `lib/agent_board/lanes.ex`), sete dias de merges (`lanes.ex`), a faixa de vazão por hora (contrato, "Throughput"), a atividade (`Board.events/2`, `board.ex:735`), o "status" falado. Nada junta o dia por executor e por custo; o que o board fez sozinho (retentativas) está em eventos, sem resumo | **Trazer** [F1.6, F4.3]: o "Resumo do dia" (feito, gasto, falhas, o que o board fez sozinho) e a revisão semanal com sugestões que o dono aprova ou recusa |
| **Alertas só em mudança de estado** | O vigia avisa a mudança, não o estado; limite de avisos por hora | O `Announcer` é um diff puro entre o board anterior e o atual, chama uma vez quando a tarefa entra em pergunta, bloqueio ou revisão, e cala enquanto ela fica (`announcer.ex:1-20`; contrato, "Silence") | **Não trazer** agora; o limite por hora só importa quando houver um canal fora do navegador |

### 2.3 Menus e navegação

| Tema | Alfred | Hoje | Veredito |
|---|---|---|---|
| **Um centro de controle só** | Um processo recebe texto, voz, canais e agendador; painel, terminal e celular são só telas | O board é esse centro para o executor DSH: uma página com o trilho de repositórios (`repo_rail.ex`), painéis por URL (`@panels`, `lib/agent_board_web/live/board_navigation.ex:9`) e as configurações atrás de um disclosure (`settings_menu.ex`). Mas só vê dois repositórios (`sallaumen/arena-rogue` e `sallaumen/o_colmex`, `GET /api/repos`) e um executor; o trabalho feito direto no Claude Code e no Codex é invisível | **Adaptar** [F1.5, F1.7, F2.1]: o board passa a ver as três ferramentas e todos os repositórios em que o dono trabalha |
| **Visão do dia, não do repositório** | A tela inicial é o assistente, não uma pasta | A navegação é por repositório; `Overview.repo_overview/0` (`board.ex:778`) já conta tarefas por estado em todos, mas só alimenta as marcas do trilho | **Trazer** [F2.1]: uma visão "Hoje" com o que precisa do dono, o que roda e onde, e o gasto, em todos os repositórios |
| **"O que você consegue fazer?" e `/uso`** | Catálogo de capacidades e um comando com tokens e custo da sessão | "O que posso pedir" (`AgentBoard.Voice.Commands`) e o painel de IA com engine, modelo, tokens e custo estimado de cada chamada do board (`lib/agent_board_web/live/board_components/ai.ex`) | **Adaptar** [F1.5]: o painel de gasto ganha os executores, não só as chamadas do board |

### 2.4 Memória

| Tema | Alfred | Hoje | Veredito |
|---|---|---|---|
| **Contexto vivo** | Contexto da conversa, compactado perto de 60 % da janela | A conversa por voz guarda turnos em `voice_turns` e dobra os antigos num resumo (`lib/agent_board/conversation.ex:46-70`, chamada `:summarize_conversation`) | **Não trazer**: existe |
| **Diário completo para consulta** | Tudo o que foi dito, com busca sem acento | Issues, comentários, eventos, `ai_calls` e os relatórios do runner já são o diário; a leitura por voz consulta parte dele | **Não trazer**; uma busca textual só se um caso real pedir |
| **Fatos curtos e duráveis, aprovados** | Uma rotina noturna propõe fatos novos e a pessoa aprova; ver, corrigir, esquecer | Não existe no board. Para o código, os fatos duráveis já são `AGENTS.md`, o contrato e o Elixir Agent Kit em cada repositório | **Adaptar** [F4.2]: fatos de roteamento e preferências ("no o_colmex, tarefas de UI vão para o Claude"), propostos pelo board a partir do histórico e aprovados pelo dono; nunca fatos sobre o código, que continuam nos repositórios |
| **Habilidades como arquivos que crescem** | Depois de três repetições, oferecer a habilidade e mostrar o arquivo antes de salvar | O kit e os prompts versionados (`docs/agent/prompts/`, `scripts/agent/prompts.sh`) já fazem isso com revisão em PR | **Não trazer** |

### 2.5 Rotinas

| Tema | Alfred | Hoje | Veredito |
|---|---|---|---|
| **Relógio de parede** | Lembrete atrasado dispara depois que o computador dormiu; nunca timer de sono | O único agendamento é o sync a cada 5 min (`config/config.exs:64-72`). O `Oban.Cron` 2.24.2 só insere um job quando a expressão casa com o minuto em que ele avalia (`deps/oban/lib/oban/cron.ex:344`): um horário perdido com o Mac dormindo não é recuperado. Para o sync isso não importa; para um resumo das 8h importa | **Trazer** como regra [F1.6]: rotina diária é "já saiu a de hoje depois das 8h?", verificado a cada tick, com a execução registrada uma vez por dia |
| **Tarefas agendadas em modo observar** | Bom-dia, relatórios e vigilância, só leitura por padrão | Nenhuma | **Trazer** [F1.6]: o resumo da manhã no board e na voz, só leitura, sem modelo por padrão |
| **Automações que o assistente cria** | Gatilhos, encadeamento, mini-apps, conectores | — | **Não trazer** (seção 5) |

### 2.6 Transparência e supervisão

| Tema | Alfred | Hoje | Veredito |
|---|---|---|---|
| **Cada chamada visível, com custo** | Nome, argumentos e resultado de cada ferramenta numa linha; qual modelo respondeu e quanto custou | Cada chamada do board é uma linha em `ai_calls` (`lib/agent_board/ai/call.ex`); o gasto do executor por tarefa vem das transcrições do DSH (`lib/agent_board/executor_usage.ex`, seção "Executor do agente" no inspetor, `inspector.ex:351-400`); a voz tem os "Bastidores da voz" | **Adaptar** [F1.1, F1.2, F1.5]: a mesma leitura para Claude Code e Codex, com contagens e custo, nunca o conteúdo das conversas |
| **Supervisor com relatório e auditoria** | Um supervisor só de leitura confere o trabalho contra regras escritas, mostra o trecho e a regra violada, sugere e a pessoa aprova | O board confere o gate local contra o sha do PR (`lib/agent_board/local_ci.ex`, contrato "Workpad") e explica cada falha (`lib/agent_board/agent_block.ex`) | **Adaptar** [F4.3]: a mesma conferência de entrega para os PRs de Claude e Codex (gate no head, `Closes #n`, merge pelo dono certo), e a correção do dono vira exemplo para o roteador |
| **Delegar ao Claude Code** | Ação vermelha; o Alfred continua dono da decisão de risco; o Claude pode pedir ao Alfred por MCP | Não existe: só o DSH executa | **Trazer** [F3.1–F3.3]: é a seção 3 |
| **Simulação antes do real** | Modo simulação nas ações | `AI_REHEARSAL` responde as chamadas do board com fixtures; nada parecido para o executor | **Adaptar** [F2.4]: o modo *sugerir* é a simulação do roteador: ele decide, registra e não despacha |

## 3. Roteamento entre DeepSeek, Claude e Codex

### 3.1 Onde o trabalho está hoje

Contagem dos últimos 7 dias pelos arquivos locais (spike de 2026-11-07, notas `alfred-usage-spike.md`):

| Ferramenta | Volume | Repositórios |
|---|---|---|
| Claude Code | 120 sessões (mais 867 arquivos de subagente) em 88 diretórios | 11, à frente forrozin-page (31), o_colmex (29), pokex (26) e agent-board (12) |
| Codex | 44 threads em 7 diretórios | 5: agent-board (14), o_colmex (13), forrozin_page (10), mtg-deck-magician-skill (5), deckex (1) |
| DeepSeek pelo board (`dsh-superagent`) | 33 tickets **no total**, todos encerrados (30 mesclados, 2 concluídos, 1 parado) | 1: `sallaumen/arena-rogue`, o único que o orquestrador vigia (`dsh:src/deployment.ts:44-54`; um repositório por orquestrador, `dsh:README.md:7`) |

O board mostra dois repositórios (`arena-rogue` e `o_colmex`) e um executor. A maior parte do trabalho do dono acontece onde o board não olha.

### 3.2 Como cada executor é acionado sem abrir a ferramenta

| Executor | Hoje | Acionamento por programa | Modelo | Verificado |
|---|---|---|---|---|
| **DeepSeek** (`dsh-superagent`) | Um comentário com `@sallaumen-agent` numa issue do repositório vigiado, lido por polling das notificações a cada 60 s ou mais (`dsh:src/sources/github.ts:128-145`), só de quem está na lista (`dsh:src/policy.ts:193-197`) | O board já faz: abre a issue com a menção no corpo (`lib/agent_board/board.ex:253`, `lib/agent_board_web/live/board_live.ex:2062`). A API do orquestrador **não cria ticket** (só o Eval cria, `dsh:docs/001-domain.md:35`) e **não responde pergunta** (a resposta é um comentário na issue); ela para, tenta de novo e pausa (`POST tickets/:id/stop`, `tickets/:id/retry`, `executor/pause`, `dsh:src/app/api.ts:35-37`) | Por papel e global (`executor.model`, `dsh:src/policy.ts:91-97`), fixado quando a sessão nasce (`dsh:docs/003-execution.md:143`); hoje `deepseek-account/deepseek-flash/high`. Não há escolha por ticket | Rotas lidas no código; `GET state`, `settings`, `tickets` e `models` lidos ao vivo |
| **Claude Code** | App desktop e CLI abertos pelo dono | `claude -p` (CLI 2.1.311): `--output-format json\|stream-json`, `--session-id <uuid>`, `--model`, `--fallback-model`, `--permission-mode`, `--allowedTools`, `--max-budget-usd`, `--add-dir`, `--append-system-prompt`, `--mcp-config`; `--max-turns` funciona mas não aparece no `--help`. O JSON final traz `session_id`, `num_turns`, `usage`, `modelUsage` e `total_cost_usd`. Chamar pelo caminho absoluto: o shim do asdf falha neste worktree. O Agent SDK (TypeScript/Python) não está instalado e não é preciso: o board fala com um processo, não com uma biblioteca | Por execução (`--model`) | Flags lidas no `--help`; o formato da saída foi lido do binário, **não de uma execução** |
| **Codex** | App desktop e extensão do VS Code | `codex exec --json -o last.txt -m <modelo> -s workspace-write -C <dir> [--ephemeral] "<prompt>"` e `codex exec resume <id>` (CLI 0.162.1). Não há flag para fixar o id da sessão: captura-se o `thread.started` do `--json` ou casa-se a linha da tabela `threads` por `cwd`, `created_at` e `source = 'exec'` (`originator = 'codex_exec'`). `exec` grava `approval_policy: never` | Por execução (`-m`); hoje `gpt-6-sol` com esforço `xhigh`, com o tráfego passando por uma URL local na porta 11434 (roteamento do Ollama) | Flags lidas; o formato dos eventos de `--json`: **não verificado** |

Duas portas laterais existem e ficam de fora do desenho: o DSH tem uma rota de modelos adormecida (`llm-pi-ai`) que falaria com Anthropic e OpenAI por chave de API (notas `alfred-dsh-api.md`), mas seria cobrança de API, global por papel, e não o Claude Code nem o Codex que o dono usa; e a interface `Executor` do DSH (`dsh:src/core/ports.ts:55-69`) permitiria outro executor, mas o runtime instancia `DshExecutor` direto (`dsh:src/app/runtime.ts:68`) e o worker depende de seis ferramentas injetadas na sessão (`dsh:src/app/tools/executor.ts:23-104`). **Conclusão: a decisão de rota fica no board, antes do executor.**

### 3.3 Onde está o uso e quanto custa

| Executor | Arquivo | Campos | Regra de contagem | Ligação com a tarefa | O que é "custo" |
|---|---|---|---|---|---|
| **DeepSeek** | `~/.dsh/sessions/<diretório do ticket>/<sessão>/session.v4.jsonl.zstd`, já lido por `AgentBoard.Usage.Harness` (#305) | `data.usage`: `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheWriteTokens` | Uma vez por `data.message.id`, worker e subagentes (contrato, "Executor usage") | Exata: diretório do ticket → ticket → issue | A conta `deepseek-account` é login de conta com saldo (carteira; falta de saldo vira `ACCOUNT_QUOTA`), não chave de API. O board estima pelo preço da sua tabela (US$ 0,28 / 0,42 por milhão, `lib/agent_board/ai/providers.ex`); sem preço de cache o valor é um mínimo, `≥` |
| **Claude Code** | `~/.claude/projects/<cwd codificado>/<sessão>.jsonl` e `<sessão>/subagents/agent-<id>.jsonl` (`isSidechain: true`) | `message.usage`: `input_tokens`, `output_tokens` (inclui pensamento), `cache_creation_input_tokens` (5 min e 1 h), `cache_read_input_tokens`, `server_tool_use`; linhas `cost-state` com `totalCostUSD` por processo | Só `type == "assistant"`, sem `model == "<synthetic>"`, **uma linha por `message.id` no conjunto todo** (cada bloco de uma mensagem repete o uso final, e uma sessão bifurcada copia as linhas do pai). Numa sessão do agent-board, 1.067 linhas viraram 372 mensagens. A soma deduplicada bateu com o `cost-state` do próprio Claude Code; chamadas laterais (Haiku) só aparecem no `cost-state` | `cwd`, `gitBranch` e `timestamp` em toda linha; linhas `pr-link` com `prNumber` e `prRepository`; numa execução do board, o `--session-id` escolhido antes | Assinatura Claude Max (`organizationType: claude_max`, `billingType: stripe_subscription`). O US$ do `cost-state` e do `total_cost_usd` é estimativa a preço de lista, não fatura. O custo real é a cota de 5 h e semanal, que **não está nos arquivos** |
| **Codex** | `~/.codex/sessions/AAAA/MM/DD/rollout-*.jsonl` (os antigos em `.jsonl.zst`) e `~/.codex/state_5.sqlite`, tabela `threads` | `token_count.info.total_token_usage`: `input_tokens` (inclui o cache), `cached_input_tokens`, `output_tokens` (inclui raciocínio), `reasoning_output_tokens`, `total_tokens`; `rate_limits`: `used_percent`, `window_minutes`, `resets_at`, `plan_type`, `credits`; `threads.tokens_used` | O total é acumulado por thread: vale o último; por dia, a diferença entre eventos. Arquivos novos (desde 2026-09-14) têm `token_usage_record` por `response_id`. `last_token_usage` repete e não se soma | `threads.cwd`, `git_branch`, `git_sha`, `git_origin_url`, `source`, `originator`. As colunas `title`, `preview` e `first_user_message` guardam texto da conversa e **nunca** são lidas | Plano ChatGPT (`auth_mode: chatgpt`, sem chave de API). Não há US$ em lugar nenhum; a moeda é o `used_percent` da janela semanal (90 % e créditos zerados na leitura mais recente) |
| **Chamadas do próprio board** | tabela `ai_calls` | tokens, `cost_micros` | uma linha por chamada (contrato, "AI calls") | `task_id` | Chave de API do provedor; US$ estimado pela tabela |

**Três moedas, não uma.** Somar o US$ de lista do Claude com o saldo gasto no DeepSeek daria um número sem sentido. A visualização e o roteador mostram cada executor na moeda que custa de fato: o DeepSeek em US$ estimado (com `≥` quando falta preço), o Claude Code em cota usada (desconhecida até alguém provar como ler, mostrada como `?`, nunca zero) com o US$ de lista como referência, e o Codex em percentual da janela semanal. Os tokens medidos são a única unidade comum, e mesmo eles medem coisas diferentes (o Codex conta o cache dentro da entrada; o DSH e o Claude, fora).

### 3.4 (a) A visualização: para onde cada tarefa foi

A unidade é a **execução**: uma sessão de um executor, atribuída a uma tarefa ou a "trabalho direto no repositório X". As regras de atribuição, da mais forte para a mais fraca:

1. **Exata**: o board despachou e guardou o id (ticket do DSH, `--session-id` do Claude, `thread.started` do Codex).
2. **Pelo PR**: a sessão tem uma linha `pr-link` (Claude) ou um branch (`gitBranch`, `threads.git_branch`) que é o branch de um PR com `Closes #n` de uma tarefa. Exige guardar o branch do PR: `pull_requests` não tem essa coluna (`lib/agent_board/board/pull_request.ex:21-32`).
3. **Pelo repositório**: `cwd` ou `git_origin_url` de um repositório do board, sem PR: "trabalho direto no o_colmex", sem tarefa.
4. **Fora do board**: um repositório que o board não conhece aparece agregado como "outros", com o nome do diretório.

Nunca se adivinha a tarefa pelo conteúdo da conversa: o leitor seleciona campos numéricos e de metadados, explicitamente, e registra só contagens.

Três telas:

- **Inspetor da tarefa, "Execuções"** (estende a seção "Executor do agente"): uma linha por execução, com executor, modelo, início e fim, tokens, custo na moeda do executor e o resultado (PR mesclado, bloqueio, falha). Uma tarefa que passou do DeepSeek para o Claude mostra as duas.
- **Painel "Executores"**: por dia (7 e 30 dias) e por executor, as tarefas, as sessões diretas sem tarefa por repositório, os tokens, o custo em cada moeda, a taxa de tarefas mescladas e o tempo até o merge. Responde "quais tarefas ficaram em cada contexto e quanto cada um gastou".
- **"Hoje"**: o que precisa do dono, o que roda e onde, e o gasto do dia, em todos os repositórios.

Ler centenas de transcrições a cada render não cabe: o contrato hoje diz que `Usage.Harness` não guarda nada e só lê com o inspetor aberto. O desenho é um **livro de uso** como o da ElevenLabs (`AgentBoard.ElevenLabs.Usage`): um job Oban numa fila própria lê os arquivos que mudaram (caminho, tamanho e mtime como chave) e grava uma linha por execução e por dia, com a origem. É dado observado guardado com a sua fonte, e muda uma regra do contrato, que o PR atualiza junto.

### 3.5 (b) O roteamento automático

**Onde decide.** No board, no momento em que a tarefa nasce (composer, voz, API). O DSH não escolhe executor nem modelo por ticket (3.2). Para o DeepSeek, despachar continua sendo abrir a issue com a menção; para Claude Code e Codex, é iniciar um runner local (3.6). Toda tarefa continua sendo uma issue no GitHub, para manter a trilha; a issue de outro executor nasce sem a menção (o DSH registra uma issue sem menção e não age, `dsh:src/policy.ts:55-58`, não testado ao vivo) e com um rótulo `executor:<nome>`.

**Sinais**, na ordem em que entram na decisão:

| Sinal | De onde vem | Peso |
|---|---|---|
| Restrição dura: o DSH só atende `arena-rogue` | `GET state` (`accounts.repository`) | Elimina o DeepSeek nos outros repositórios |
| Escolha explícita do dono ("manda pro Claude") e fatos aprovados ("no o_colmex, UI vai para o Claude") | O pedido; a tabela de fatos (F4.2) | Decide quando existe |
| Disponibilidade | Orquestrador no ar, pausado e `load.running` contra `maxWorkers` (`Orchestrator.load/0`, já lido); binário e login presentes; última `rate_limits` do Codex (`used_percent`, `rate_limit_reached_type`); `ACCOUNT_QUOTA` no DSH; um runner livre por executor | Elimina quem não pode atender agora |
| Orçamento | Gasto do dia por executor no livro de uso contra o teto de cada um | Elimina quem passou do teto |
| Tipo e tamanho da tarefa | O split do composer já é uma chamada registrada (`:propose_tasks`); ganha os campos `tipo` (UI, backend, docs, bug, pesquisa, infra) e `tamanho` (P, M, G), sem chamada nova | Escolhe a linha do histórico |
| Histórico por repositório, tipo e executor | Livro de uso + resultado das execuções: taxa de mescladas sem correção, tempo até o merge, bloqueios e perguntas, retrabalho (tarefa filha por `origin_task_id` em 7 dias), custo por tarefa mesclada | Ordena os que sobraram |
| Custo esperado | Mediana do custo de tarefas parecidas, na moeda do executor | Desempata e aparece na confirmação |

A primeira versão é uma função pura, `AgentBoard.Routing.suggest/2`: regras na ordem acima, sem modelo. Ela devolve o executor, os motivos em frase, as alternativas e o custo esperado. Cada sugestão vira uma linha em `routing_decisions` (tarefa, sugerido, escolhido, modo, motivos, a foto dos sinais e quem decidiu); essa tabela é a base da medição.

**Modos** (a escada de confiança do Alfred, aplicada a um só tipo de decisão):

1. **Sugerir** (o inicial). O composer mostra "Sugestão: Claude Code, porque o DSH não atende o o_colmex e o Codex está com 90 % da cota semanal". O dono confirma ou troca; o despacho é a ação confirmada, com os valores ("Mandar #412 para o Claude Code no o_colmex, teto US$ 3?").
2. **Confirmar**. O board escolhe; o dono aprova cada despacho com um toque, ou um lote.
3. **Automático por categoria**. Oferecido, nunca ligado sozinho, quando uma combinação de repositório e tipo junta 10 sugestões seguidas aceitas cujo resultado foi bom; a primeira troca feita pelo dono ou o primeiro resultado ruim devolve a categoria ao modo anterior. Fica visível numa tela, com o histórico de cada subida e descida.

**Como medir se a escolha foi boa.** Para cada execução: mesclou sem correção humana; tempo até o merge; quantas perguntas e bloqueios; quantas retentativas; retrabalho em 7 dias; custo na moeda do executor. Para o roteador: a taxa de aceitação das sugestões e, nas trocas, o resultado do executor que o dono escolheu contra a mediana do que o roteador sugeriu naquela categoria. Rodar a mesma tarefa em dois executores para comparar custaria o dobro e fica de fora; a troca feita pelo dono é o rótulo que ensina.

**Fallback quando um executor falha**:

| Falha | O que acontece |
|---|---|
| Transitória antes de gastar (rede, 5xx, processo que não subiu) | Mesmo executor; no DSH a retentativa automática que já existe; nos runners, uma nova tentativa só se nenhum token foi gasto |
| Indisponível (cota da assinatura, `ACCOUNT_QUOTA`, binário sem login, orquestrador fora) | O board propõe o próximo da lista com o motivo e o custo; nos modos sugerir e confirmar, o dono aprova; no automático, só se a categoria permite e antes de qualquer gasto |
| De conteúdo (testes falham, bloqueio, pergunta) | Nunca troca sozinho: vai para Precisa de você. "Reenviar para o Codex" é uma ação confirmada que continua o mesmo branch |
| Teto atingido no meio | O runner para (`--max-budget-usd` no Claude; no Codex, só pelo tempo, porque não há teto em US$) e a tarefa entra em Precisa de você com o gasto |

Uma tarefa nunca tem duas execuções ao mesmo tempo.

### 3.6 A fronteira nova: o board despachando

> **Estado (2026-11-08):** esta fronteira virou o
> [ADR 0004](../decisions/0004-o-board-despacha-para-executores-locais.md)
> (D1, D2, D3 e D5 decididas) e F3.1–F3.3 e F3.5 estão implementadas — ver
> [contrato — Dispatch](../maintainer-contract.md#dispatch-despacho-local).
> F3.4 segue como trabalho separado.

Hoje o board lê o agente e escreve no runner por dois caminhos de API (contrato, "Boundaries"). Iniciar o Claude Code ou o Codex é uma escrita nova, que gasta, e pede um ADR antes do código, com estas regras propostas:

- **O processo não é filho do board.** O serviço reinicia a cada atualização (`launchctl kickstart`), e um processo aberto por `Port` corre o risco de morrer junto (inferência, não testado). O board pede ao runner, um script com a sessão num tmux ou num job do launchd, como o `dsh-superagent` já roda, e depois só observa: o arquivo de resultado, a transcrição, o worktree e o PR.
- **Despachar é uma ação do registro de ações** (F2.3), confirmada com executor, repositório, teto e custo esperado, salvo no modo automático daquela categoria.
- **O orçamento é checado antes de iniciar**, como `Budget.check/1` antes da rede; o teto vai na linha de comando quando a CLI aceita.
- **Uma execução, uma linha**, com o id da sessão e a decisão que a originou. Nenhuma retentativa de execução paga sem uma decisão.
- **Pausar despacho** é um interruptor global: o que roda continua, nada novo sai.
- **O mesmo contrato de entrega para os três**: o prompt do runner vem de `docs/agent/prompts/` (o workpad `## Relatório do agente`, o gate local no head e a política de merge), então Precisa de você, o CI local e o "Mesclados" funcionam igual para qualquer executor.

## 4. Plano por fases

Esforço: **P** ≤ meio dia · **M** 1–2 dias · **G** > 2 dias. Cada item é uma issue ou um PR. A ordem vai do mais barato e valioso ao mais ambicioso: primeiro o board **vê** as três ferramentas, depois **sugere**, depois **despacha**, por fim **decide sozinho** onde já provou acertar.

### Fase 0 — Decisões do dono (sem código)

| # | Decisão | Por que trava | Precisa de |
|---|---|---|---|
| D1 | O board pode iniciar Claude Code e Codex locais por uma ação confirmada (a fronteira da seção 3.6)? | Sem isso a fase 3 não existe; as fases 1 e 2 não dependem dela | O dono |
| D2 | Tetos: orçamento mensal (o perfil do Alfred dizia US$ 300 por mês; vale para a plataforma?), teto por tarefa em cada executor e a reserva de cota das assinaturas para o uso direto | O roteador e os runners checam antes de iniciar | O dono |
| D3 | Usar a assinatura Claude Max em `claude -p` e o plano ChatGPT em `codex exec`, para uso pessoal, despachado pelo board | Termos de uso das assinaturas; nenhuma credencial nova | O dono confirma os termos |
| D4 | Quais repositórios entram no board (hoje 2; o dono trabalhou em 11 na semana) | Atribuição e "Hoje" dependem disso; o sync gasta cota da API do GitHub por repositório | **Decidido em 2026-11-07: só os atuais**, `sallaumen/arena-rogue` e `sallaumen/o_colmex`. Uso de Claude e Codex em outros repositórios aparece como fora do board, sem tarefa |
| D5 | Quem abre e mescla os PRs de Claude e Codex: o bot `sallaumen-agent` (como o DSH) ou a conta do dono; e se vale a mesma política de merge do DSH | Os runners precisam de um `gh` autenticado com escrita | O dono; se for o bot, o token dele no ambiente do runner |

### Fase 1 — Ver as três ferramentas (só leitura)

| # | Item e onde | Esforço | Valor | Depende de | Risco | Pronto quando |
|---|---|---|---|---|---|---|
| F1.1 | **Leitor de uso do Claude Code**: `AgentBoard.Usage.ClaudeCode` lê `~/.claude/projects/**/*.jsonl` (sessões e subagentes), deduplica por `message.id` no conjunto, agrupa por sessão, dia, `cwd` e `gitBranch`; testes com transcrições sintéticas | M | Alto: o maior volume de trabalho do dono passa a ter número | — | Formato interno do Claude Code muda numa versão nova; volume de arquivos (milhares) | A soma de uma sessão real bate com o `cost-state` dela; nenhum campo de texto é lido (teste que falha se o leitor tocar `message.content`) |
| F1.2 | **Leitor de uso do Codex**: `AgentBoard.Usage.Codex` lê `threads` (colunas explícitas, via Exqlite como o `AgentState`) e os rollouts (`zstd` para os antigos), por diferença do total acumulado; guarda o último `rate_limits` | M | Alto: o Codex entra no quadro, com a cota semanal visível | — | Roteamento pelo Ollama pode alterar campos (não verificado); a lacuna de 247 mil tokens num arquivo recente | `tokens_used` de duas threads bate com o último total; `title`, `preview` e `first_user_message` fora de toda consulta |
| F1.3 | **Livro de uso**: tabela por execução e por dia, job Oban numa fila `usage` que lê só os arquivos alterados (caminho, tamanho, mtime); o DSH entra reaproveitando o parser de `Usage.Harness`; seção nova no contrato | M | Alto: base de tudo o que vem depois | F1.1, F1.2 (pode nascer junto de um deles) | Mudar a regra "Usage.Harness não guarda nada" sem deixar duas fontes de verdade | Reler os mesmos arquivos não muda nenhuma linha; um arquivo novo aparece em até um ciclo; o contrato descreve o livro |
| F1.4 | **Branch do PR e atribuição**: coluna `head_ref` em `pull_requests` (o sync já busca o PR) e as quatro regras de atribuição da seção 3.4 | P | Médio: liga sessões diretas a tarefas | — | PR sem `Closes #n` fica sem tarefa (é o comportamento certo) | Uma sessão do Claude que abriu o PR de uma tarefa aparece nela, por `pr-link` ou branch |
| F1.5 | **Painel "Executores" e "Execuções" no inspetor** (seção 3.4), cada executor na sua moeda, `?` para o desconhecido | M | Alto: responde "para onde foi e quanto custou" por tarefa, dia e executor | F1.3, F1.4 | Ler como fatura o que é estimativa: cada valor diz se é medido, estimado ou desconhecido | O dono vê os últimos 7 dias dos três executores sem abrir nenhuma ferramenta |
| F1.6 | **Resumo do dia com relógio de parede**: a cada tick, "já saiu o de hoje depois das 8h?"; feito, gasto por executor, falhas, o que o board fez sozinho (retentativas); no board e na voz; template sem modelo | P/M | Médio: o relatório diário do Alfred, sem canal novo | F1.3 só para a linha de gasto (o resto sai antes) | Disparar duas vezes depois de um reinício: a execução do dia é uma linha única | Com o Mac dormindo às 8h, o resumo sai ao acordar, uma vez |
| F1.7 | ~~**Repositórios do dono no board**~~: não se aplica pela decisão D4 (só os repositórios atuais); reabrir se o dono mudar de ideia, adicionando pela API existente (`POST /api/repos`) e medindo o custo do sync | — | — | D4 | — | — |

### Fase 2 — O board sugere, o dono escolhe

| # | Item e onde | Esforço | Valor | Depende de | Risco | Pronto quando |
|---|---|---|---|---|---|---|
| F2.1 | **Visão "Hoje"** em todos os repositórios, a partir de `Overview.repo_overview/0` e do livro de uso | M | Alto: a tela inicial deixa de ser um repositório | F1.3 | Uma leitura a mais por render: entra na mesma leitura do board (contrato, "Real-time") | O que precisa do dono nos repositórios aparece numa lista só, com o repositório em cada item |
| F2.2 | **Executor na tarefa**: campo `executor` (`dsh`, `claude`, `codex`), escolha no composer e na voz, rótulo `executor:<nome>` na issue; a issue de outro executor nasce sem a menção | M | Alto: o dono já cria tudo no board, mesmo antes do despacho existir | — | O DSH agir numa issue sem menção (não esperado, não testado ao vivo) | Uma tarefa `claude` vira issue sem menção e com rótulo; o DSH não a pega |
| F2.3 | **Registro de ações com risco**: `AgentBoard.Actions` com cada escrita do board, seu risco, a frase com os valores reais e o registro da decisão; UI, voz e API passam por ele; recusar vermelho sem confirmação no código | M | Alto: o portão do Alfred, e o pré-requisito para despachar algo que gasta | — | Regressão nas confirmações que já funcionam (voz, `AgentAction`) | Um teste por ação; a mesma frase de confirmação na tela e na voz; nenhuma escrita fora do registro |
| F2.4 | **Roteador em modo sugerir**: `AgentBoard.Routing.suggest/2` (puro) e a tabela `routing_decisions`; o composer mostra a sugestão, os motivos e o custo esperado | M | Alto: começa a medir se o board escolheria bem, sem risco | F1.3, F2.2 | Sugestão óbvia demais no começo (sem histórico, só regras) | Toda tarefa criada tem uma linha com sugerido, escolhido e motivos |
| F2.5 | **Tipo e tamanho no split**: campos novos no schema de `:propose_tasks` no registry, sem chamada nova | P | Médio: sinal para o roteador e para os relatórios | — | O modelo classificar mal: o dono corrige na revisão, e a correção vira dado | O campo aparece no recibo do composer e na tarefa |

### Fase 3 — O board despacha

| # | Item e onde | Esforço | Valor | Depende de | Risco | Pronto quando |
|---|---|---|---|---|---|---|
| F3.0 | **ADR 0004, "O board despacha para executores locais"**, e a seção nova do contrato (regras da 3.6) | P | Alto: destrava a fase | D1, D2, D3, D5 | — | ADR aceito pelo dono |
| F3.1 | **Runner do Claude Code**: script em `scripts/runners/` que cria o worktree, roda `claude -p --session-id … --output-format json --max-budget-usd …` num tmux, grava o resultado; `AgentBoard.Runners` inicia pela ação confirmada e observa arquivos, transcrição e PR | G | Muito alto: o primeiro trabalho no Claude sem abrir o Claude | F3.0, F2.2, F2.3 | Permissões: em headless o Claude precisa de um modo sem perguntas, o mesmo nível de risco do DSH (`danger-full-access`); um reinício do board não pode matar a execução | Uma tarefa no o_colmex vira PR mesclado pelo runner, com a execução e o custo no inspetor, e o board reiniciado no meio não a interrompe |
| F3.2 | **Runner do Codex**: o mesmo encaixe com `codex exec --json`, capturando o id da thread | M | Alto | F3.1 | Sem teto em US$ no Codex: limite por tempo e pela cota semanal | Idem F3.1 com o Codex |
| F3.3 | **Pausar despacho e uma execução por tarefa**: interruptor global e trava por tarefa; tetos checados antes de iniciar | P | Alto: o botão de parada do Alfred | F3.1 | — | Com a pausa ligada nada novo sai; uma segunda execução da mesma tarefa é recusada |
| F3.4 | **Objetivo**: um grupo de tarefas com critério de pronto, progresso calculado das tarefas, podendo atravessar executores; o composer cria o objetivo quando o split devolve mais de uma tarefa | M | Médio/alto: o "objetivo em segundo plano" do Alfred | F2.2 | Virar um segundo gerenciador de projeto: o objetivo não tem estado próprio além do critério | O board diz "objetivo X: 3 de 5 tarefas mescladas" sem nada escrito à mão |
| F3.5 | **Fallback e retentativa nos runners** (tabela da 3.5) | M | Alto: uma cota esgotada deixa de parar o trabalho | F3.1, F3.2 | Gastar duas vezes: nenhuma retentativa depois de gasto sem decisão | Um Codex sem cota faz o board propor o Claude com o motivo e o custo |

### Fase 4 — O board decide onde já provou acertar

| # | Item e onde | Esforço | Valor | Depende de | Risco | Pronto quando |
|---|---|---|---|---|---|---|
| F4.1 | **Modos confirmar e automático por categoria**, com a oferta depois de 10 acertos seguidos e a volta no primeiro erro (3.5) | M | Muito alto: é o objetivo do dono | F2.4, F3.1–F3.5 e semanas de histórico | Subir sem prova: o board só oferece; quem liga é o dono | Uma categoria no automático despacha sem perguntar e volta ao modo sugerir na primeira troca |
| F4.2 | **Fatos aprovados de roteamento**: tabela pequena, proposta pelo board a partir do histórico, aprovada, corrigida ou apagada pelo dono | M | Médio: preferências viram regra visível | F2.4 | Fatos velhos: cada um mostra a data e a origem | "No o_colmex, UI vai para o Claude" aparece como motivo da sugestão |
| F4.3 | **Revisão semanal de 10 minutos**: por executor e tipo, as trocas do dono, as falhas e as mudanças de regra sugeridas, que o dono aprova ou recusa; a conferência de entrega (gate no head, `Closes #n`) também para os PRs de Claude e Codex | M | Médio | F1.5, F2.4 | — | Uma sugestão aprovada muda uma regra do roteador e fica registrada |
| F4.4 | **Board como servidor MCP só de leitura** para as sessões diretas ("o que está na fila?", "quanto gastei hoje?") | M | Baixo/médio | F1.5 | Expor dado do board além do localhost | Uma sessão do Claude Code lê a fila do board sem escrever nada |

### Paralelismo e o que precisa do dono

- **Podem começar já, em paralelo:** F1.1, F1.2, F1.4, F1.6 (sem a linha de gasto), F2.3 e F2.5. Nenhum precisa de decisão nem de credencial.
- **Em sequência:** F1.3 depois de F1.1 e F1.2; F1.5 depois de F1.3 e F1.4; F2.4 depois de F1.3 e F2.2; a fase 3 inteira depois de F3.0; F4.1 depois de semanas de `routing_decisions`.
- **Precisa do dono:** D1 a D5. Credencial nova só em D5, se os runners usarem o bot: o token do `sallaumen-agent` no ambiente do runner. Os logins do Claude Max e do ChatGPT já existem nesta máquina.
- **Arquivos compartilhados**: F1.3, F1.4, F2.2 e F2.5 trazem migração; duas sessões não devem escrever migrações ao mesmo tempo sem combinar o timestamp. F2.3 mexe em `BoardLive`, `Conversation` e no controller, e não deve correr junto de outro item que mexa nesses arquivos.

## 5. O que não fazer

- **Telegram e outros canais (WhatsApp, Slack, Discord), por ora.** Decisão do dono em 2026-11-07. O que fica adiado: avisos fora do navegador, responder pergunta ou aprovar pelo celular e criar tarefa por mensagem. Quando voltar, o canal entra como mais uma porta do registro de ações (F2.3), com lista de remetentes e a mesma confirmação, e a implementação do Pokex é a referência. Antes disso, a API do board não deve sair do `127.0.0.1`: hoje ela escreve sem autenticação.
- **Não construir o motor do Alfred** (Python, FastAPI, um motor de agente de terceiros, o Hermes do perfil, um VPS). O board já é o centro de controle; trocar a base custaria tudo o que existe e não traria o roteamento, que é o que falta.
- **Não deixar o assistente escrever automações, mini-apps ou conectores para si.** Choca com "toda chamada de modelo está no registry" e com o contrato do board.
- **Não controlar o computador pela tela** nem dar shell ao board. Quem mexe em código são os executores, nos seus worktrees.
- **Não trocar o modelo do DSH a cada ticket** com `PUT settings/executor`: é global e daria corrida entre tickets. Nem ligar a rota `llm-pi-ai` do DSH com chaves de API para "ter Claude no DSH": seria cobrança de API e não o Claude Code que o dono usa.
- **Não rodar Claude Code ou Codex como processo filho do board** (seção 3.6).
- **Não ler o conteúdo das conversas para atribuir sessões**: só metadados e números, com campos escolhidos um a um.
- **Não somar moedas** nem mostrar zero para o desconhecido: cota sem leitura é `?`, preço que falta deixa o custo como mínimo (`≥`).
- **Não deixar o modelo confirmar nada nem subir a autonomia.** A confirmação vem do dono; o board só oferece a subida.
- **Não rodar a mesma tarefa em dois executores para comparar.** A troca feita pelo dono é o rótulo.
- **Não usar um modelo local para classificar tarefas** (o perfil do Alfred citava Ollama com Llama). As regras e a chamada de split que já existe bastam; reavaliar só se as regras errarem demais.
- **Não usar o Claude Agent SDK com o login da assinatura** num produto: o caminho pessoal é o `claude -p` com o login do próprio dono (D3).

## 6. Perguntas em aberto

> **Atualização de 2026-11-08:** D1, D2, D3 e D5 foram respondidas no
> [ADR 0004](../decisions/0004-o-board-despacha-para-executores-locais.md).
> As perguntas 6–8 seguem em aberto.

1. O board pode iniciar Claude Code e Codex nesta máquina (D1)? Se não, as fases 1, 2 e 4.2–4.4 ainda valem, e o despacho fica manual.
2. Qual é o orçamento mensal da plataforma e o teto por tarefa de cada executor (D2)? Quanto da cota das assinaturas fica reservado para o uso direto do dono?
3. Os termos das assinaturas cobrem execuções headless disparadas pelo board, para uso pessoal (D3)?
4. ~~Quais repositórios entram no board (D4)?~~ Respondida em 2026-11-07: só os atuais.
5. Quem abre e mescla os PRs de Claude e Codex, e com que política (D5)?
6. O DSH deve ganhar mais repositórios (um orquestrador por repositório) ou os outros repositórios ficam com Claude e Codex?
7. O que conta como "boa escolha" para o dono: mesclar sem correção em quantas horas, com que custo máximo?
8. Como ler a cota da assinatura do Claude sem abrir o app? Sem isso, o Claude entra no roteador com disponibilidade desconhecida.

## 7. Não verificado

- A saída real de `claude -p --output-format json` e de `codex exec --json`: o formato foi lido do binário e do `--help`, sem execução paga.
- O que `--max-budget-usd` limita numa conta de assinatura (o `--help` fala em "API calls"; a estimativa a preço de lista é o candidato).
- Onde ler a cota de 5 h e semanal do Claude Max sem a interface; e quando o Claude Code grava as linhas `cost-state`.
- O efeito do roteamento pela porta 11434 (Ollama) nos campos de uso e de cota do Codex; a lacuna de 247.213 tokens entre os `token_usage_record` e o total num arquivo recente; os valores de `--thread-source`.
- Se a conta `deepseek-account` é pré-paga ou assinatura, e os preços reais do `deepseek-flash` e do cache.
- Se um processo aberto por `Port` morre quando o launchd reinicia o board (a seção 3.6 assume que sim, por cautela).
- Se o DSH ignora, ao vivo, uma issue sem menção no repositório que vigia (o código diz que só registra, `dsh:src/policy.ts:55-58`).
- Quem disparou as 8 sessões `sdk-cli` encontradas nas transcrições do Claude Code.
- Os termos de uso das assinaturas para execuções headless (pergunta 3).

## 8. Como reproduzir os spikes

Só leitura; nenhum comando abaixo imprime texto de conversa nem segredo.

```sh
# versões e flags
claude --version; claude --help | grep -E 'max-budget|output-format|session-id|fallback-model|permission-mode'
codex --version;  codex exec --help | grep -E -- '--json|--cd|--ephemeral|--sandbox'

# Claude Code: uma sessão, deduplicada por message.id (só números)
F=$(ls -t ~/.claude/projects/-Users-tavano-projects-agent-board*/*.jsonl | head -1)
jq -c 'select(.type=="assistant" and .message.model!="<synthetic>")
       | [.message.id, .message.usage.input_tokens, .message.usage.output_tokens,
          .message.usage.cache_creation_input_tokens, .message.usage.cache_read_input_tokens]' "$F" \
  | awk -F, '!seen[$1]++ {u++; i+=$2; o+=$3; w+=$4; r+=$5} END {print u, i, o, w, r}'
grep -l '"type":"cost-state"' ~/.claude/projects/*/*.jsonl | wc -l

# Codex: threads por origem (nunca title, preview ou first_user_message)
sqlite3 -readonly ~/.codex/state_5.sqlite \
  "select source, originator, count(*), sum(tokens_used) from threads group by 1, 2;"
jq -r '.auth_mode' ~/.codex/auth.json     # só o modo, nunca os tokens

# DSH: estado e modelos (GET apenas)
curl -s -H 'x-orchestrator-request: 1' http://127.0.0.1:3082/orchestrator/api/state | jq 'keys, .load, .paused'
curl -s -H 'x-orchestrator-request: 1' http://127.0.0.1:3082/orchestrator/api/models | jq '.routableProviders'

# Oban.Cron não recupera horário perdido
grep -n 'Expression.now?' deps/oban/lib/oban/cron.ex
```
