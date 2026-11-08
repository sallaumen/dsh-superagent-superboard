# Plano: a voz do agente falando com o dono

> **Registro histórico:** plano de 6 de novembro de 2026, anterior à
> implementação. Os itens marcados "(escolhido)" já foram entregues; as regras
> vigentes estão em [maintainer-contract.md](maintainer-contract.md#the-voice) e o
> uso atual em [voice-conversation.md](voice-conversation.md). Os itens adiados
> (B6, B7, U6) seguem adiados.

Workflow do kit: `notifications` (o que é falado, quando, quantas vezes e por
que se repete). Data: 2026-11-06.

## O que existe hoje

- `AgentBoard.Announcer` decide o que falar quando o board muda;
  `BoardLive.speak/2` empurra `voice_play` e o hook `VoicePlayer` toca o mp3
  de `/api/voice/speech` (ElevenLabs).
- Sem chave ElevenLabs, só o resumo do botão "falar" usa a voz do navegador
  (`phx:speak`, `utterance.lang = navigator.language`).

## Problemas observados no código

| # | Problema | Onde |
|---|---|---|
| 1 | Toda frase falada é inglês ("Task 'X' is now running.", "Good morning", "The sync failed") enquanto títulos e voz são português: a mistura vem daqui. | `Voice`, `Announcer`, `BoardLive` |
| 2 | O prompt `summarize_board` não diz o idioma; o modelo responde no idioma que quiser. | `AI.Registry` |
| 3 | O TTS não força idioma: Flash v2.5 aceita `language_code` e normaliza números e siglas no idioma certo. | `ElevenLabs.speech/2` |
| 4 | Uma tarefa que passa a `question` (o agente esperando sua resposta) não é anunciada: `question` não está nas lanes vivas. | `Announcer` |
| 5 | Duas mudanças no mesmo update viram dois `voice_play`; o segundo cancela o primeiro, então a primeira frase nunca é ouvida. | `BoardLive.announce/3` + `VoicePlayer.play` |
| 6 | A saudação usa a hora UTC: às 22h em São Paulo (01h UTC) o agente diz "Good morning". | `Voice.greeting/1` |
| 7 | Volume não existe; o resumo não conta perguntas pendentes. | `VoicePanel`, `Voice.summary/2` |

## Opções

Backend

- **B1 Idioma da voz** (escolhido): chave `voice_language` (`pt-BR` padrão,
  `en-US`); todas as frases faladas saem de `AgentBoard.Voice.Phrases`; o
  prompt do resumo recebe o idioma; o TTS manda `language_code` no Flash.
- **B2 Chamadas de atenção** (escolhido): tarefa que entra em pergunta,
  bloqueio ou revisão vira um chamado, com 10 frases por tipo em rodízio
  (nunca a mesma duas vezes seguidas) e prioridade sobre as outras notícias.
- **B3 Uma fala por atualização** (escolhido): as frases do mesmo update viram
  uma só, então nenhuma é cortada.
- **B4 Fala mais natural** (escolhido): estados com nome falado ("em
  andamento", "na fila"), título curto cortado em palavra, saudação pela hora
  local do navegador, resumo conta perguntas.
- **B5 Volume** (escolhido): chave `voice_volume` 0–100, validada, também em
  `PUT /api/voice/settings`.
- B6 Lembrete: repetir o chamado se a tarefa seguir esperando por N minutos.
  Adiado: precisa de um relógio por tarefa e de um limite para não virar
  insistência.
- B7 Horário silencioso. Adiado.

Interface

- **U1 Volume** (escolhido): slider com porcentagem, aplicado na hora ao áudio
  que estiver tocando.
- **U2 Idioma** (escolhido): seletor no topo da seção Voz; ao trocar, o agente
  confirma no idioma novo.
- **U3 Dois interruptores** (escolhido): "Chamar quando precisar de mim" e
  "Narrar o resto do quadro", separados, para quem quer só os chamados.
- **U4 Painel em português** (escolhido): a seção já se chama "Voz"; o
  conteúdo estava em inglês.
- **U5 Voz do navegador como reserva** (escolhido): sem chave ElevenLabs, os
  chamados usam a voz do navegador no idioma escolhido.
- U6 Um som curto antes do chamado. Adiado.

## Depois: a sua fala para o agente

O caminho inverso (ditado → comando) fica para a próxima rodada. O primeiro
passo natural é mandar o idioma escolhido como dica ao Scribe
(`/api/voice/transcribe?language=pt`), que já aceita o parâmetro.
