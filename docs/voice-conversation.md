# A conversa por voz com o agente

Workflow do kit: `async-state` (cada fala tem dono, chave e desfecho).
Data: 2026-11-07.

## É possível conversar enquanto o agente mexe no código?

Sim, e o desenho já separa as duas coisas. O board (este app Phoenix) e o
agente que escreve código (`dsh-superagent`) são processos diferentes. A
conversa roda no board: ela lê o quadro e responde. O único caminho dela até o
código é o mesmo de um botão: abrir uma issue (que o agente pega sozinho),
parar ou arquivar uma tarefa. Falar com o board nunca interrompe um ticket
rodando, nunca entra no worktree e nunca escreve na sqlite do agente.

## Como se usa

1. Espaço duas vezes (com o board em foco, ou no título do painel de voz).
   Um som curto subindo avisa que o microfone abriu.
2. Fale e pare. Depois da pausa escolhida (0,8 / 1,2 / 1,8 s; padrão 1,2 s) a
   fala é considerada pronta e vai sozinha, com um som descendo; sem fala por
   8 s o microfone fecha. As barras mostram o nível real do microfone.
   Espaço duas vezes de novo envia na hora; Esc cancela.
3. O agente responde em voz. Enquanto ele pensa, Esc cancela a resposta. Se a
   resposta pede um sim (criar, parar, arquivar) ou uma dúvida, o microfone
   reabre uma vez sozinho para a resposta.

## Ajustes (Configurações → Voz)

Idioma, volume, velocidade (0,8–1,2×), entonação (estável, natural,
expressiva), pausa para enviar, os chamados de atenção, a narração do resto do
quadro e o som ao abrir e fechar o microfone.

Não há rascunho para revisar nem Enter. O painel "Comando de voz" mostra a
conversa para quem quiser ler, aceita texto digitado e tem "Esquecer conversa".

## O que ele sabe fazer

| Você diz | Ele faz | Escreve algo? |
|---|---|---|
| "Como está o quadro?", "o que está bloqueado?" | responde com o quadro atual | não |
| "Abre a tarefa 42" | abre a conversa da tarefa | não |
| "Muda para o arena rogue" | troca de projeto | não |
| "Cria uma tarefa no arena rogue para mostrar o volume" | refina o pedido (`Intake.refine`), diz o título e pergunta "Posso criar?" | só depois do seu sim |
| pedido vago | faz uma pergunta antes de propor | não |
| "Para a tarefa 7" / "Arquiva a 7" | diz qual é e pergunta "Posso?" | só depois do seu sim |
| "sim", "pode", "manda" / "não", "deixa pra lá" | confirma ou cancela a proposta pendente (reconhecido localmente, sem modelo) | a ação confirmada |
| "Esquece a conversa" | apaga a memória | apaga as falas |

A confirmação falada fica porque uma transcrição errada não pode abrir issue
sozinha; ela custa uma palavra e mantém a conversa natural.

## O contexto

- **Memória durável**: `voice_turns` guarda cada fala (`owner`, `agent`). Um
  reload ou outra aba mantém o contexto.
- **O modelo lê**: o resumo mais recente + as 16 últimas falas, a proposta
  pendente e um retrato compacto do quadro (projeto atual, projetos, tarefa
  aberta, até 8 tarefas por raia com totais exatos, merges recentes, sync).
- **Resumo**: quando passam de 28 falas depois do último resumo, as mais
  antigas viram um novo resumo (`:summarize_conversation`). Se o resumo falhar,
  nada se perde: o contexto só fica mais longo.
- Títulos e falas antigas são dados, nunca instruções (dito no prompt).

## Ciclo de uma fala

| Transição | Dono | Registro durável |
|---|---|---|
| ouvindo → enviada | hook `VoiceCommand` (silêncio encerra) | — |
| enviada → pensando | `VoiceConversation.start/2`, chave `ref` | `voice_turns` (owner) |
| pensando → respondida | `finish/3`, só para o `ref` atual | `voice_turns` (agent, com proposta se houver) |
| pensando → superada | uma fala nova cancela a anterior; o resultado velho é descartado | — |
| pensando → expirada | `{:voice_turn_timeout, ref}` (45 s) | — |
| proposta → confirmada/cancelada/expirada | `Conversation.settle/2`, condicional, uma vez; expira em 10 min | `proposal_status` |

Um "sim" repetido (evento duplicado, duas abas) não cria duas issues: só quem
move a proposta de `proposed` executa, e `Board.create_request/3` ainda
deduplica pela chave.

## Tempo de resposta

Medido em 2026-11-07 (WebKit, voz Flash v2.5, modelo `deepseek-flash`):

| Etapa | Antes | Depois |
|---|---|---|
| Criar tarefa: refinar o pedido | chamada extra de 5,1–6,9 s (`refine_request`) | dentro da mesma chamada `voice_agent` (título e critérios) |
| Primeiro som da resposta | arquivo inteiro: 0,59–1,13 s | stream: 0,41–0,43 s; frase repetida, do cache: ~0,02 s |
| Pausa para enviar | fixa em 1,2 s | ajustável: 0,8 / 1,2 / 1,8 s |

O resto do caminho: transcrição (Scribe) ~0,9 s e o modelo 1,4–2,1 s, que
cresce com o tamanho da resposta (130–310 tokens de saída); por isso a
resposta falada é curta. O JSON compacto da entrada não mudou a contagem de
tokens de forma mensurável. Cada fala
do agente guarda quanto ele pensou (`duration_ms`), mostrado no histórico, e a
voz mostra "Respondi em X s" contado do fim da sua fala ao primeiro som.

No WebKit um stream sem tamanho toca até o fim mas nunca dispara `ended`; o
player considera a fala terminada quando ela para de avançar por 1 s.

## Qualidade da voz

- O que o agente fala passa por `AgentBoard.Voice.Speakable`: sem markdown,
  `#42` vira "42", `dono/repo-nome` vira "repo nome", links saem.
- Sem chave ElevenLabs, o navegador usa a melhor voz que tiver no idioma
  (exata, depois "enhanced/premium/natural"), com a velocidade escolhida.

## Próximos passos possíveis

- Interromper a fala do agente falando por cima (barge-in), sem espaço duplo.
- Perguntar a uma tarefa (comentário para o agente de código) pela conversa,
  com confirmação.
- Escolher a sensibilidade do silêncio nas configurações.
