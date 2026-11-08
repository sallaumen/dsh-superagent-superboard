# ADR 0004 — O board despacha para executores locais

- **Decisão:** o board pode despachar uma tarefa para o Claude Code ou o
  Codex locais por uma **ação confirmada** do registro de ações, com
  orçamento e cota checados antes de iniciar, um processo que não é filho do
  board e uma linha por execução. O board continua observando; ele não fala
  com o modelo nem controla a máquina.
- **Estado:** **aceita em 2026-11-08 pelo dono**. D1, D2, D3 e D5 foram
  respondidas (abaixo) e a Fase 3 está implementada em `AgentBoard.Runners`;
  o ADR registra a fronteira e o contrato em "Dispatch (despacho local)".
- **Escopo:** as regras da seção 3.6 de
  [`docs/research/alfred.md`](../research/alfred.md); não altera o contrato
  nesta entrega.

## Problema e contexto

O board já vê as três ferramentas e já sabe para onde uma tarefa deve ir:

| Peça | Estado em 2026-11-07 |
|---|---|
| Executor na tarefa, issue sem menção e rótulo `executor:<nome>` (F2.2) | implementado |
| Registro de ações com risco, frase de confirmação e decisão gravada (F2.3) | implementado |
| Livro de uso por execução e dia, com atribuição por PR e branch (F1.3, F1.4) | implementado |
| Roteador sugerindo por regras e registrando a decisão (F2.4) | implementado |
| Tipo, tamanho e custo esperado no composer (F2.5, F2.4) | implementado |
| Resumo do dia e visão Hoje (F1.6, F2.1) | implementado |
| Alguém iniciar Claude Code ou Codex por programa | **não existe** |

O DSH é o único executor que o board aciona sozinho, e o faz por um caminho
que já existe: abre a issue com a menção e o orquestrador a encontra
(`docs/research/alfred.md`, 3.2). Para Claude Code e Codex não há mencionável:
o acionamento é `claude -p` e `codex exec`, processos locais que gastam a
assinatura do dono. Fazer isso é uma escrita nova, que gasta, e por isso
precisa de um ADR antes do código (o contrato, "Board actions", já exige que
toda escrita passe pelo registro).

O que limita o desenho:

- O serviço reinicia a cada atualização (`launchctl kickstart`); um processo
  aberto por `Port` pode morrer junto com o board.
- As duas assinaturas são pessoais: Claude Max e o plano ChatGPT. Não há
  chave de API nova, e o custo real é uma cota que os arquivos não guardam.
- O board só mostra dado observado; o estado de uma execução tem de ser lido
  do que o runner deixar (arquivo de resultado, transcrição, worktree, PR).
- Uma tarefa não pode ter duas execuções ao mesmo tempo, e nenhuma
  retentativa paga pode acontecer sem uma decisão.

## As regras propostas

Estas são as regras da seção 3.6 do plano, em forma de contrato.

1. **O processo não é filho do board.** O board pede ao runner — um script
   em `scripts/runners/` com a sessão num `tmux` ou num job do `launchd`,
   como o `dsh-superagent` já roda — e depois só observa: o arquivo de
   resultado, a transcrição, o worktree e o PR. Reiniciar o board não
   interrompe a execução.
2. **Despachar é uma ação do registro.** É vermelha, com a frase que nomeia
   executor, repositório, tarefa, teto e custo esperado
   (`AgentBoard.Actions`). A confirmação existe na tela, na voz e na API; o
   modo automático por categoria (F4.1) é a única exceção, e só depois de o
   dono ligá-lo.
3. **O orçamento é checado antes de iniciar.** Um `Budget.check/1` do
   executor, separado do orçamento das chamadas do board, compara o gasto do
   dia e do mês com o teto. O teto vai na linha de comando quando a CLI
   aceita (`--max-budget-usd` no Claude Code); o Codex, que não tem teto em
   US$, tem teto de tempo e a cota semanal como limite.
4. **Uma execução, uma linha.** Cada execução nasce de uma linha em
   `routing_decisions` e grava o id da sessão, o início, o fim e o resultado
   no livro de uso. Nenhuma retentativa paga sem uma decisão nova; uma
   tarefa nunca tem duas execuções ao mesmo tempo.
5. **Pausar despacho é um interruptor global.** Com a pausa ligada, o que
   roda continua e nada novo sai. A trava por tarefa e a pausa são checadas
   antes do runner, não dentro dele.
6. **O mesmo contrato de entrega para os três.** O prompt do runner vem de
   `docs/agent/prompts/` (o workpad `## Relatório do agente`, o gate local no
   head e a política de merge), então "Precisa de você", o CI local e
   "Mesclados" funcionam igual para qualquer executor.
7. **Falha não vira troca silenciosa.** Transitória antes de gastar: o mesmo
   executor. Indisponível ou teto: o board propõe o próximo com motivo e
   custo; no automático, só antes de qualquer gasto. Falha de conteúdo
   (teste, bloqueio, pergunta) nunca troca sozinha: vai para Precisa de você,
   e "Reenviar para o Codex" é uma ação confirmada que continua o mesmo
   branch.
8. **Credencial é do dono e não entra em código, log ou prompt.** Se D5
   escolher o bot, o token dele fica no ambiente do runner; o board não
   guarda nem imprime segredo.
9. **Nada disso sai do localhost.** A API do board não ganha autenticação
   neste ADR; o despacho é acionado pelo dono na máquina dele.

## Decisões do dono (2026-11-08)

| # | Decisão | Resposta |
|---|---|---|
| **D1** | O board pode iniciar Claude Code e Codex locais por uma ação confirmada? | **Sim.** A ação vermelha `dispatch_task`, com a frase e o teto, é a única porta. |
| **D2** | Orçamento mensal, teto por tarefa e reserva das assinaturas | **US$ 300/mês, US$ 5 por tarefa no Claude Code, 30 minutos no Codex e 50 % da cota semanal reservada**, todos configuráveis no formulário de Configurações → Despacho local (`dispatch_*`); nenhum valor é somado entre executores. |
| **D3** | Os termos das assinaturas cobrem execução headless para uso pessoal? | **Sim, para uso pessoal**, confirmado pelo dono; nenhuma credencial nova é criada. |
| **D5** | Quem abre e mescla os PRs? | **A conta do dono**, com o `gh` já autenticado e a mesma política de entrega do DSH; o token do bot não entra no runner. |

D4 (quais repositórios entram no board) já estava respondida: só
`sallaumen/arena-rogue` e `sallaumen/o_colmex`; uso em outros repositórios
aparece como "fora do board", sem tarefa.

Perguntas menores que ficam para a operação: ler a cota do Claude sem abrir
o app (hoje desconhecida), o tempo máximo de uma execução antes do aviso de
silêncio e a variante do prompt por executor.

## Alternativas

| Alternativa | Benefício | Custo ou risco |
|---|---|---|
| Deixar o despacho manual (o dono abre Claude Code e Codex) | Nenhuma credencial, nenhum processo novo, nenhum risco de termo | O board não fecha o ciclo; o dono continua abrindo a ferramenta, que é o que a fase 3 quer evitar |
| O board inicia o processo como filho (`Port`/`System.cmd`) | Implementação local mais simples, sem tmux nem launchd | Um reinício do board pode matar a execução; contraria "o processo não é filho do board" e a atualização do serviço |
| Usar o Agent SDK (TypeScript/Python) com o login da assinatura | API mais rica que o CLI | O SDK não está instalado, e usar a assinatura num produto é justamente o que a seção 5 do plano proíbe; o CLI `claude -p` é o caminho pessoal |
| Usar a rota `llm-pi-ai` do DSH com chaves de API | Um lugar só para os modelos | Seria cobrança de API, global por papel, e não o Claude Code nem o Codex que o dono usa |
| Um runner por executor, com ação confirmada e orçamento (proposta) | Mantém o board como centro de controle, preserva a observação e a trilha | Exige os quatro processos (Claude, Codex, pausa, teto) e as respostas D1–D3 e D5 |

## Escolha e consequência

A proposta mantém o board no papel que ele já tem: o centro de controle que
**observa** e **pede**, nunca o processo que executa. O runner é um detalhe
trocável; o contrato é o registro de ações, o orçamento antes do gasto e uma
linha por execução. O dono aceitou D1–D3 e D5 em 2026-11-08; a
implementação entrou em PRs separados, na ordem do plano:

F3.1 (runner do Claude Code, worktree, `--session-id`, resultado e
observação), F3.2 (runner do Codex, `codex exec --json` e captura da thread),
F3.3 (pausa global e uma execução por tarefa) e F3.5 (classificação da falha,
retentativa e troca de executor só com uma nova confirmação) estão
implementados e testados. F3.4 (objetivo com critério de pronto) continua
como trabalho separado.

## Riscos e limites

- **Termos das assinaturas:** o risco maior não é técnico; D3 foi confirmada
  pelo dono para uso pessoal, e o despacho continua local, sem produto.
- **Cota compartilhada:** uma execução despachada consome a mesma cota que o
  dono usa à mão; D2 decidiu reservar 50 % da janela semanal do Codex, e o
  Claude Code tem teto por tarefa e por mês.
- **Processo sobrevivente:** o runner precisa de um lugar que sobreviva ao
  board e ao logout; tmux ou launchd, nunca um `Port`.
- **Máquina do dono:** o runner roda com as permissões que o DSH já usa
  (`danger-full-access`); o board não ganha shell nem controle de tela.
- **Dados:** o livro de uso continua sem ler texto de conversa; o runner
  entrega o resultado pelo workpad e pelo PR, não por um canal novo.
- **Custo de errar:** uma execução perdida no meio pode deixar worktree e
  branch; a limpeza já existe em `scripts/agent/cleanup.sh` e continua sendo
  do dono.

## Implantação e revisão

A primeira entrega foi o ADR e a linha no índice; a implementação veio em
PRs separados (`AgentBoard.Runners`, o script `scripts/runners/run.sh`, a
ação `dispatch_task`, a pausa e a observação) e a seção "Dispatch (despacho
local)" do contrato. Revisar quando:

- o dono quiser mudar os tetos, a reserva ou o modelo padrão;
- o Claude Code ou o Codex mudarem o formato de `--json`/`cost-state` (o
  leitor do livro de uso já cobre o que existe hoje);
- a cota da assinatura puder ser lida sem abrir o app — o roteador deixa de
  tratar a disponibilidade do Claude como desconhecida.

Referências: [`docs/research/alfred.md`](../research/alfred.md) seções 3.4,
3.5, 3.6 e 4; [`docs/maintainer-contract.md`](../maintainer-contract.md)
seções "Board actions", "Executors", "Routing", "Usage ledger" e
"Attribution"; [`ADR 0003`](0003-ciclo-de-vida-do-agente.md) para o ciclo de
vida e a retentativa automática que já existe.
