# ADR 0003 — Ciclo de vida do agente em quatro situações de borda

- **Decisão:** registrar, com citação de arquivo e linha, o que o `dsh-superagent` e o board fazem quando a issue é fechada durante o run, quando o DSH reinicia com uma Assignment `running`, quando uma segunda menção chega na mesma issue e quando o PR do ticket é fechado sem merge; e propor as regras que o [contrato](../maintainer-contract.md) passa a ter para cada caso. O contrato não muda neste PR.
- **Estado:** proposta. O comportamento está documentado; as regras ficam pendentes de um PR no contrato e de código no board.

## Problema e contexto

A pesquisa [`docs/research/symphony.md`](../research/symphony.md) (seção 5, frente 3) concluiu que ninguém sabia responder o que o DSH faz nessas quatro situações, e que isso é o que mais vai doer ao paralelizar (`executor.maxWorkers > 1`). O `SPEC.md` do openai/symphony (commit `be10a1b`) foi usado como checklist, não como modelo: §7 (estados), §8 (tick, reconciliação, dispatch obsoleto), §14 (falhas e reinício) e §18 (checklist de conformidade).

Fontes lidas, todas por leitura estática; nada foi executado:

| Lado | Arquivos | Prefixo nas citações |
|---|---|---|
| DSH (`/Users/tavano/Documents/deepseek-harness/default-workspace/dsh-superagent-prototype`) | `src/core/tickets.ts`, `intake.ts`, `assignments.ts`, `model.ts`, `stage.ts`; `src/executor/dsh.ts`; `src/sources/github.ts`, `github-trigger.ts`, `github-pull.ts`; `src/app/effects.ts`, `runtime.ts`; `docs/001-domain.md`, `002-authorization.md`, `003-execution.md`, `007-architecture.md`; `prompts/`; `tests/core-engine.spec.ts` | `dsh:` |
| Board (este repositório) | `lib/agent_board/sync.ex`, `live.ex`, `agent_state.ex`, `board.ex`, `work.ex`, `sync/freshness.ex`, `board/task.ex`; `docs/maintainer-contract.md`; `test/agent_board/sync_repo_test.exs` | sem prefixo |
| Symphony | `SPEC.md` em `be10a1b` | `SPEC.md:` |

Vocabulário do DSH (`dsh: docs/001-domain.md:35-37`): um **Ticket** é aberto até ter `ended` (`model.ts:318`); uma **Assignment** vai `pending → running → ended` por conta própria (`model.ts:211,218-233`); o ticket termina com um `outcome` em `completed | merged | closed | dropped | stopped` (`model.ts:271-273`); uma **Subscription** faz toda mensagem na Thread chegar ao ticket como **Input**, e uma mensagem humana ressuscita um ticket encerrado sem novo Eval (`001:37`, `002:125-129`).

## As quatro situações

### 1. A issue é fechada no GitHub enquanto o ticket está `running`

**O que o DSH faz: nada.** O fechamento de uma issue não vira Trigger, Input nem fim de ticket.

- A fonte GitHub lê a issue em dois lugares, e nos dois só olha autor, data de criação e comentários desde o cursor: `readNotified` (`dsh: src/sources/github.ts:344-374`, corpo só se criada depois do cursor em 355-356, comentários em 357) e `pollThread` (`github.ts:440-459`, issue lida só para preencher `isPr` e título em 446-451). O campo `state` existe no schema (`github-trigger.ts:34-38`) e não é consultado em nenhum caminho; os únicos usos de `.state` são de PR (`github-pull.ts:48,58`).
- O único fim de ticket vindo da fonte é `threadClosed`, chamado apenas por `closePull` (`github-pull.ts:80-84`), que roda para os PRs dos tickets abertos (`github.ts:404-413`), nunca para issues. `docs/003-execution.md:92-106` lista como um ticket termina: relatório `ready`/`dropped`, fechamento de PR, stop. Issue fechada não está na lista.
- O worker não é avisado: `prompts/` e `skills/` não mencionam issue fechada (as únicas ocorrências de "closed" são `prompts/subscriptions.md:5` e `prompts/dispatch.md:10`, ambas sobre PR).
- Logo o worker continua, e o ticket termina com o que o worker fizer depois: `ready` sem PR → `completed`; `ready` com PR → espera o PR fechar e termina `merged` ou `closed` (`dsh: src/core/assignments.ts:129-132`, `tickets.ts:77-90`); `dropped` → `dropped`. Um PR aberto para uma issue fechada fica aberto até uma pessoa agir.
- Worktree e PR ficam. O único `rmdir` do executor é o de um diretório vazio após um `prepare` que falhou (`dsh: src/executor/dsh.ts:255-259`); nenhum fim de ticket remove o diretório. O SPEC exige o oposto: estado terminal no tracker → parar o worker e limpar o workspace (`SPEC.md:831-839` §8.5 B, `841-849` §8.6, `1713-1715` §14.4, `2228-2229` §18.1), e o próprio worker reconfere o estado da issue a cada turno (`SPEC.md:662-674` §7.1).

**O que o board mostra hoje.**

- O botão **Parar** do board fecha a issue e marca a task `stopped` (`lib/agent_board/board.ex:353-366`); o cliente do orquestrador é só leitura (`docs/maintainer-contract.md:16`, `:262`), então o board nunca chama o stop do DSH (`dsh: src/core/tickets.ts:160-163`). Pelo item acima, o agente continua trabalhando. A task `stopped` sai de todo overlay (`sync.ex:439`, `live.ex:86`): o board diz "parado" enquanto o worker roda e pode abrir um PR.
- Se a issue foi fechada direto no GitHub: o sync só substitui `title`, `url` e `updated_at` de uma task existente (`sync.ex:259-262`); "closed → done" vale só no primeiro insert (`sync.ex:247-258`; o teste `test/agent_board/sync_repo_test.exs:527-537` cobre só esse caso). `apply_overlay` recusa um overlay que não seja `done` numa issue fechada (`sync.ex:433-434`), mas o poller de 10 s não conhece o estado da issue e aplica `running` mesmo assim (`live.ex:74-101`). A task fica "rodando" até o worker relatar, depois "para revisar", e só vira `done` por um PR mesclado ou fechado (`board.ex:60-86,96-121`). Com `completed` (ready sem PR) fica "para revisar" para sempre.

**O que o board deveria mostrar.** Uma task cujo ticket está vivo numa issue fechada, inclusive depois do Parar do board, aparece em "Precisa de você" com o motivo "o agente continua nesta issue fechada; o board não o parou" e a ação que resolve (parar pela API do DSH, se o contrato passar a permitir uma escrita; senão o comando `scripts/dsh-superagent` ou o painel do DSH). "Parado" só quando o SQLite mostrar `ended.by == "human"`.

**Não verificado.** A leitura é inequívoca no código, mas não houve execução. Experimento: abrir uma issue de teste com `@sallaumen-agent` e um pedido de alguns minutos; quando `scripts/agent/tickets.sh 1` mostrar `progress`, rodar `gh issue close N`; esperar dois polls (`pollSeconds`, 60 s por padrão); no SQLite (`$STATE_DIR/orchestrator.sqlite`, `scripts/agent/_common.sh:3-5`) conferir que `json_extract(value,'$.ended')` segue nulo e `$.inputs` não ganhou entrada; deixar o worker terminar e conferir o PR aberto e o worktree em `work/<nome>`; no board, conferir `tasks.state` em cada fase e repetir com o Parar do board no lugar do `gh issue close`.

### 2. O DSH reinicia com uma Assignment `running`

**O que o DSH faz: retoma, com nota de recuperação; nada fica órfão e nada vira `failed`.**

- Na subida, `Runtime` chama `executor.resume()` (`dsh: src/app/runtime.ts:214`). Para cada ticket aberto com Assignment `running`, o executor cancela o turno da sessão mantendo a caixa de entrada, para os jobs e reporta `assignmentInterrupted` (`dsh: src/executor/dsh.ts:524-537`).
- `Assignments.interrupted` (`dsh: src/core/assignments.ts:83-92`): se o último relatório não é `waiting|ready|blocked|failed`, ou um Input chegou depois dele (`busy`), a Assignment termina com `endedReason: 'hostRestarted'` e nasce uma nova `pending` com a nota de recuperação (`assignments.ts:21`: inspecionar worktree, git e GitHub antes de repetir ação externa) à frente dos Inputs que esperavam (`tickets.ts:318-337`); se o relatório estava assentado e nada chegou depois, a sessão é mantida e só os Inputs pendentes são entregues. `docs/003-execution.md:144-152` descreve isto; `tests/core-engine.spec.ts:701-732` prova os dois ramos.
- O launch é um efeito durável em SQLite (`dsh: src/app/effects.ts:42-45`); o `drain` de desligamento deixa as linhas para a próxima subida (`effects.ts:98-102,136-137`). O launch reaproveita a mesma sessão `worker-<ticket>` e o mesmo diretório; a mensagem da segunda Assignment diz só o que é novo (`dsh.ts:449-464`). Contraste com o SPEC: o Symphony não persiste nada e redespacha a partir do tracker (`SPEC.md:1690-1704` §14.3; `2239` §18.2 lista a persistência como TODO). Aqui o DSH é mais forte que o checklist.
- Enquanto o processo está **caído** (sem reinício), o SQLite não muda: `assignments[-1].state == "running"`, `idleAt` nulo se o turno estava no meio.

**O que o board mostra hoje.**

- `AgentState.normalize` lê a última Assignment (`lib/agent_board/agent_state.ex:134-162`); `running_ticket?` é `assignment == "running"` com `idle_at` nulo (`sync.ex:524-525`); o overlay `running` é reaplicado a cada 10 s (`live.ex:36,74-101`). Durante toda a queda a task diz "rodando".
- O frescor usa o mtime do WAL como batimento (`agent_state.ex:60-81`): com ticket `running` e sem escrita há mais de `agent_running_ttl` (120 s, `sync/freshness.ex:14,76-80`) o cabeçalho vai a "Dados atrasados" e a fonte "Processo do agente" diz "Sem sinal" (`freshness.ex:182-194`). O card da task não muda. A API do orquestrador (`AgentBoard.Orchestrator.load/0`, `maintainer-contract.md:219`) responderia "fora do ar" no mesmo instante, mas o frescor não a consulta.
- Depois do reinício: a nova Assignment nasce `pending`, `ticket_state` devolve `nil` e o card fica no estado anterior ("rodando") até o launch marcá-la `running` (`assignments.ts:34-43`). O `startedAt` novo avança `tasks.started_at` (`sync.ex:448-455`, `live.ex:95-100`), e a métrica Fila, que conta da entrada até `started_at` (`maintainer-contract.md:217`), passa a usar o relógio da retomada.

**O que o board deveria mostrar.** Com ticket `running` e orquestrador inalcançável (API fora ou WAL parado além do TTL), o card diz "agente fora do ar; o ticket retoma no reinício", não "rodando"; o frescor pergunta à API antes de acusar "Sem sinal" por um turno longo. `tasks.started_at` é o `startedAt` da **primeira** Assignment, para que reinício e retry não zerem a fila.

**Não verificado.** (a) Se o DSH escreve no SQLite durante um turno longo sem relatório: o `Passes` roda a cada 2 s (`dsh: src/app/passes.ts:28`) mas só escreve quando há trabalho; um turno de três minutos sem Input pode acusar "Sem sinal" falso. (b) A sequência exata no board. Experimento: com um ticket em `progress` e `idleAt` nulo, parar o DSH (`scripts/dsh-superagent stop`); conferir `tasks.state` e o cabeçalho aos 30 s e aos 150 s; subir de novo; conferir no SQLite `assignments[#-2].endedReason == 'hostRestarted'`, `assignments[#-1].state` passando por `pending` e `running`, o input `text` com "The host restarted" e `undelivered` esvaziando; conferir `select started_at from tasks where number = N` antes e depois. Repetir com um ticket `waiting`: `assignments` deve continuar com uma entrada só.

### 3. Uma segunda menção chega na mesma issue durante o run

**O que o DSH faz: entrega a mensagem ao worker em curso. Sem Eval, sem ticket novo, sem Decision.**

- A segunda menção chega como comentário, pela notificação (`dsh: src/sources/github.ts:344-374` e `intakeComments` em 384-403) ou pelo poll das Threads assinadas (`github.ts:429-459`), em ≤ `pollSeconds`; `commentTrigger` marca `addressed: 'mention'` (`github-trigger.ts:65-76`).
- Na entrada (`dsh: src/core/intake.ts:19-62`): o ticket assinou `github:<n>` ao nascer (`tickets.ts:52`), então o Trigger faz fan-out (`intake.ts:34-52`) e vira Input via `addInput` (`tickets.ts:234-245`), que pede a entrega ao executor. Como o ticket vivo é dono da mensagem (`model.ts:75-88`), ela **não** vai para Eval (`intake.ts:56-58`). `docs/002-authorization.md:20-26`: a sessão principal recebe um aviso de follow-up e só pode parar o trabalho.
- A entrega (`dsh: src/executor/dsh.ts:290-343`) injeta a mensagem na sessão do worker com `steer` (342), relendo o ticket antes de cada envio. Worker ocioso (`waiting`) é acordado no slot extra reservado a pessoas (`dsh.ts:305-309,171-199`). Worker `blocked`/`failed`: a mensagem humana levanta `waitsForPerson` (`model.ts:349-353`) e é entregue (`tickets.ts:237-241` segura só Inputs automáticos).
- O worker decide: atende dentro do escopo ou devolve com `orchestrator_trigger_handback` (`002:28-34`, `tickets.ts:106-115`); só então a mensagem vai a Eval e pode virar outro ticket na mesma issue (o domínio admite vários tickets por Thread: `001:52`). Testes: `tests/core-engine.spec.ts:186-262` (fan-out) e `359-700` (follow-ups, donos e hand-back). Não há paralelo no SPEC: o Symphony não tem mensagens, só o estado da issue.

**O que o board mostra hoje.** Nada muda em `ticket_state` (`sync.ex:481-491`): o overlay segue `running` (ou `question`, se o último comentário do agente perguntar, `board.ex:472-491`). O comentário aparece na conversa após o sync de 5 min (`sync.ex:83`). O board não diz que a mensagem foi entregue ao worker nem se ele a devolveu. Como as tasks são por número de issue, não nasce task duplicada.

**O que o board deveria mostrar.** Um marcador "follow-up entregue ao agente às HH:MM" (do `inputs[]` com `kind: trigger` e `human: true` depois de `startedAt`, `readAt` dizendo se o worker já leu) e, se houver hand-back (`disposition.handbacks`), "devolvido: <motivo>; aguardando avaliação". Nunca uma segunda task para a mesma issue.

**Não verificado.** A latência real e a leitura mid-turn. Experimento: com um ticket `progress` na issue N, comentar "@sallaumen-agent também X" dentro do escopo; em ≤ 60 s, no SQLite, `$.inputs` ganha `{kind: trigger, human: true, deliveredTo: <assignment atual>}` e `readAt` preenche no próximo passo do worker; a tabela `disposition` tem `fanout = [ticket]` sem `evalId`; as tabelas `decision` e `ticket` não ganham linha. Repetir com um pedido fora do escopo: `disposition.handbacks` ganha a entrada e `thread.pending` recebe o Trigger; conferir se nasce um ticket cujo `origin.triggerId` é esse comentário.

### 4. O PR do ticket é fechado sem merge por uma pessoa

**O que o DSH faz: encerra o ticket com `outcome: 'closed'`, mantém assinaturas, worktree e branch.**

- A cada poll, `pollTicketPulls` lê os PRs dos tickets abertos (`dsh: src/sources/github.ts:404-413`); `observePull` vê `state == 'closed'` sem `merged` (`github-pull.ts:57-69`) e `closePull` reporta `threadClosed(..., 'closed', closed_at)` (`github-pull.ts:80-84`).
- `Tickets.threadClosed` (`dsh: src/core/tickets.ts:77-90`) grava `follows[].closed`; se não resta PR próprio aberto (`followsDone`, 95-101) e o trabalho não está inacabado (`unfinished`, 370-379: retomada ou retry depois do fechamento, ou follow-up humano assumido sem relatório posterior), chama `end(ticket, 'executor', 'closed', closed_at)` (345-363): toda Assignment vira `ended`, e `executor.stop` cancela o turno a menos que a última palavra tenha sido `ready`/`dropped` sem Input depois, e mata os jobs (`dsh.ts:357-370`). Teste: `tests/core-engine.spec.ts:1087-1116`; o ramo "merge durante follow-up assumido" em `541-559`.
- A Subscription fica (`github-pull.ts:77-79`, `001:37`): um comentário humano no PR fechado ou na issue ressuscita o ticket sob o mesmo Mandate (`tickets.ts:252-270`, `intake.ts:40-46`), com a nota `RESUMED` (`dsh.ts:132-135`). Um PR reaberto volta a ser seguido (`github-pull.ts:63-65`, `003:98`). Nenhum código remove o worktree (ver caso 1). O aviso de encerramento vai só a canais de chat; no GitHub o PR já mostra (`github-pull.ts:90-105`). No SPEC, o equivalente é o estado terminal: parar e limpar (`SPEC.md:803-811` §8.4, `831-839` §8.5).

**O que o board mostra hoje.** `ticket_state` só distingue `merged` (`sync.ex:484`); um ticket encerrado `closed` cujo último relatório foi `ready` cai em `"ready"` (`sync.ex:487`), então o poller de 10 s mantém a task "para revisar" com um PR fechado até o próximo sync. No sync, `reconcile_resolved_tasks` (`board.ex:96-121`) trata PR `closed` igual a `merged` (`board.ex:81`): a task vira `done`, cujo rótulo é "mesclado" (`board.ex:664`), e entra em "Concluídas" (`maintainer-contract.md:212`). O estado `closed` existe na lista (`board/task.ex:9`) e nada o atribui.

**O que o board deveria mostrar.** `closed` ("fechado sem merge"), fora de "Concluídas" e de "Precisa de você", com a dica "um comentário na issue ou no PR retoma o ticket" e o link do worktree que sobrou (dado ao script de limpeza da frente 4).

**Não verificado.** A sequência ao vivo e o tempo até `ended`. Experimento: com um ticket `ready` cujo `follows[]` tem o PR com `own: true`, `gh pr close P`; em ≤ 60 s conferir `follows[].closed.outcome == 'closed'` e `ended == {by: executor, outcome: closed, at: <closed_at>}`; conferir `tasks.state` aos 10 s ("ready") e após o sync ("done"); comentar na issue como humano e conferir que `ended` some e nasce uma Assignment `pending`.

## Resumo

| Situação | DSH faz | Board mostra hoje | Board deveria mostrar |
|---|---|---|---|
| Issue fechada durante o run | Nada: não lê `state` da issue; worker continua; ticket termina pelo que o worker relatar; worktree e PR ficam | "rodando", depois "para revisar"; `done` só por PR; com Parar do board, "parado" enquanto o agente roda | "agente continua em issue fechada; não foi parado" em Precisa de você; "parado" só com `ended.by == human` |
| Reinício com Assignment `running` | `resume` → Assignment termina `hostRestarted`, nova `pending` com nota de recuperação na mesma sessão e worktree; `waiting`/`ready`/`blocked`/`failed` sem Input novo mantém a sessão | "rodando" durante a queda; "Sem sinal" no cabeçalho após 120 s; `started_at` avança no reinício | "agente fora do ar; retoma no reinício"; frescor confirma pela API; `started_at` da primeira Assignment |
| Segunda menção na mesma issue | Fan-out ao worker vivo como Input (`steer`); sem Eval, ticket ou Decision; o worker atende ou devolve | Nenhuma mudança de estado; comentário só após o sync | "follow-up entregue às HH:MM" / "devolvido: motivo"; nunca uma segunda task |
| PR fechado sem merge | `threadClosed` → `ended.outcome == closed`; Assignments encerradas; assinaturas, worktree e branch ficam; comentário humano retoma | "para revisar" por até 5 min, depois `done` rotulado "mesclado" e contado em Concluídas | `closed` ("fechado sem merge"), fora de Concluídas, com "um comentário retoma" |

## Alternativas

| Alternativa | Benefício | Custo ou risco |
|---|---|---|
| Deixar como está: o board espelha o último relatório | Nenhuma mudança | "parado", "mesclado" e "rodando" falsos nos casos 1, 4 e 2; ao paralelizar, cada caso multiplica |
| O board passa a escrever no DSH (stop pela API) | Parar vira real | Quebra "o board só lê" (`maintainer-contract.md:262`); exige o contrato mudar e a API aceitar escrita autenticada |
| O board deriva o estado de `ended.outcome` e da vivacidade do orquestrador, e diz o que não fez (escolhida) | Honesto e só leitura; cabe no modelo de duas camadas | Não resolve o worker rodando em issue fechada: isso é do DSH |
| Mudar o DSH para reconciliar issue fechada como o SPEC (§8.5 B) e limpar worktrees terminais | Fecha a lacuna na origem | Fora deste repositório; fica como sugestão upstream |

## Decisão

As regras abaixo são a proposta para `docs/maintainer-contract.md`, seção "The data" e uma seção nova "The agent's lifecycle". Este PR não edita o contrato.

1. **O estado da task segue `ended.outcome` quando o ticket encerrou:** `merged` → `done`; `closed` → `closed` (fechado sem merge; não conta em Concluídas); `stopped` → `stopped`; `completed` → `ready` com a nota "sem PR"; `dropped` → baseline da issue com a nota "o agente não fez nada". Hoje só `merged` é lido (`sync.ex:484`).
2. **Um ticket só está "parado" quando o SQLite diz `ended.by == "human"`.** O Parar do board fecha a issue e marca a task; se o ticket seguir vivo, a task aparece em Precisa de você com "o agente continua; o board não o parou" até o ticket encerrar. Se o contrato um dia autorizar uma escrita no DSH, é esta, e só esta.
3. **Um ticket `running` com o orquestrador inalcançável é "fora do ar", não "rodando".** A vivacidade vem da API (`Orchestrator.load/0`) e do mtime do WAL; o board diz qual das duas falhou.
4. **`tasks.started_at` é o `startedAt` da primeira Assignment do ticket**, nunca o da retomada ou do retry.
5. **Uma segunda menção nunca cria uma segunda task.** O board mostra o follow-up a partir de `inputs[]` (entregue, lido, devolvido), sem escrever no SQLite.
6. **O sync atualiza o estado de uma task existente quando a issue fecha** (`upsert_issue` passa a substituir `state` nesse caso), respeitando `stopped` e `archived`.

## Escolha e consequência

O board continua um espelho (`maintainer-contract.md:262`): nenhuma regra acima escreve no SQLite nem na API do DSH. O que muda é o que o espelho mostra: o `outcome` em vez do último relatório, a vivacidade do processo em vez do mtime sozinho, e a verdade sobre o Parar. As lacunas que só o DSH fecha, reconciliar a issue fechada (`SPEC.md:831-839`) e limpar worktrees terminais (`SPEC.md:841-849`), ficam registradas aqui como sugestão para o repositório do DSH; a frente 4 (script de limpeza, `docs/research/symphony.md` §5) cobre a limpeza por fora enquanto isso.

Achado lateral, para uma issue à parte: `scripts/agent/tickets.sh` lê `assignments[0]` e o board lê a última Assignment (`agent_state.ex:136`); depois de um reinício ou retry o script mostra o relatório antigo (já anotado em `docs/research/symphony.md` §5).

## Implantação e revisão

Este PR: o ADR e a linha no índice. Depois, em PRs separados: (1) as regras no contrato; (2) `ticket_state/2` lendo `closed`, `completed` e `dropped`, com testes em `sync_test.exs`; (3) o Parar honesto; (4) a vivacidade pela API no frescor; (5) `started_at` da primeira Assignment; (6) `upsert_issue` com `state` na issue fechada. Antes de (2) a (6), rodar os quatro experimentos acima com um ticket de teste e anotar o resultado neste ADR. Reconsiderar quando `executor.maxWorkers` subir de 1 e quando o DSH passar a reconciliar issues fechadas.
