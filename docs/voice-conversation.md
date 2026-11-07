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

## Quando o agente de código responde

Uma pergunta mandada pela conversa fica esperando a resposta por até um dia.
A resposta é o primeiro comentário novo do agente naquela tarefa que não é o
workpad (o agente edita o workpad no lugar e responde a uma pergunta direta
com um comentário novo). O board fala um resumo de poucas frases uma vez só,
mesmo com várias abas abertas, e a resposta entra na memória da conversa. A
sincronização traz comentários a cada 5 minutos, então a resposta pode ser
falada até uns minutos depois de aparecer no GitHub. O interruptor "Chamar
quando uma tarefa precisar de mim" também silencia esse aviso.

## Ajustes (Configurações → Voz)

Idioma, volume, velocidade (0,8–1,2×), entonação (estável, natural,
expressiva), pausa para enviar, os chamados de atenção, a narração do resto do
quadro e o som ao abrir e fechar o microfone.

Não há rascunho para revisar nem Enter. O painel "Conversa por voz" mostra a
conversa para quem quiser ler, aceita texto digitado e tem "Esquecer conversa".
A antiga caixa de comando (rascunho em inglês com "Check command") saiu em
2026-11-07: tudo que ela fazia passa pela conversa.

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
| "Pergunta pro agente da tarefa 12 se ele já rodou os testes" | diz a pergunta e pergunta "Posso mandar?"; com o sim, comenta na issue com `@sallaumen-agent`; quando o agente responder, fala a resposta ("O agente da tarefa 12 respondeu: …") | só depois do seu sim |
| "Repete" / "pode repetir?" | fala de novo a última resposta (local, sem modelo) | não |
| "Fala mais devagar" / "mais rápido" / "mais alto" / "mais baixo" | ajusta velocidade (±0,1) ou volume (±20) e confirma já na voz nova (local) | o ajuste |
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

## Diagnóstico: logs e bastidores

- **Na tela**: o painel "Conversa por voz" tem "Bastidores da voz", ao vivo por
  PubSub: cada etapa de uma fala com o tempo (fala, transcrição, modelo,
  ação, voz), cada re-tentativa e cada erro, inclusive os do navegador
  (microfone, reprodução). Abre sozinho quando há um erro recente.
- **No log** (`~/Library/Logs/AgentBoard.log` no serviço da 4099): as mesmas
  linhas, com data e hora, por exemplo
  `2026-11-07 12:01:02.123 [warning] voice stage=tts status=retry attempt=2 reason="HTTP 503" — nova tentativa em 300 ms`.
  Para ver só a voz: `grep "voice stage=" ~/Library/Logs/AgentBoard.log`.
- **Nível**: `LOG_LEVEL` (`debug`, `info`, `warning`, `error`). O serviço
  roda em `info`; em `debug` o dev registra cada consulta SQL (foi o que
  levou o log a quase 1 GB).
- **Re-tentativas**: só ElevenLabs, só falhas sem cobrança (conexão, 429,
  5xx), no máximo duas, e um stream só antes do primeiro byte.

## Próximos passos possíveis

- Interromper a fala do agente falando por cima (barge-in), sem espaço duplo.
  Hoje espaço duplo durante a fala já interrompe e abre o microfone.
- Decidir se a avaliação de `answer_board_question` (`scripts/eval-board-ai.exs`)
  passa a avaliar `voice_agent`, que é o que a voz usa agora.

## Custo da voz

- **Onde se paga**: a ElevenLabs cobra caracteres de TTS (cada fala gerada) e
  segundos de áudio de STT (cada transcrição). O modelo (DeepSeek) entra nas
  linhas de `ai_calls` e no orçamento de IA, não aqui.
- **O livro-caixa** (`AgentBoard.ElevenLabs.Usage`, tabela
  `eleven_labs_usage`, uma linha por dia UTC): `AgentBoard.ElevenLabs` soma
  cada resposta 200 paga, com os caracteres do header `x-character-count` (ou
  o tamanho do texto, sem o header) e os segundos de `audio_duration_secs`;
  o `VoiceController` conta as falas servidas do cache, que custam zero. Uma
  falha re-tentada não entra: não foi cobrada.
- **Onde ver**: o resumo de "Bastidores da voz" (por exemplo
  "hoje: 3.420 de 20.000 caracteres · 1,2 min transcritos · 18 do cache") e
  `GET /api/voice/status` (`usage` e `daily_char_cap`).
- **O teto diário**: `ELEVENLABS_DAILY_CHAR_CAP` (padrão 20000 caracteres,
  `0` desliga). A chamada que cruza o teto registra um evento
  "teto diário atingido…" uma vez por dia. O teto não recusa nada sozinho:
  `Usage.over_cap?/0` é o sinal para a fala passar para a voz grátis do
  navegador.
- **Pagar uma vez**: o cache de falas curtas (até 300 caracteres) tem a
  memória (ETS, 150 entradas, uma semana) na frente da tabela
  `voice_speech_cache` (1000 linhas, 30 dias desde o último uso). As frases
  fixas (chamados, confirmações, erros) são pagas uma vez, não a cada
  restart. A chave é a mesma de sempre: texto, voz, modelo, idioma,
  velocidade e entonação; mudar qualquer um é outra fala.
