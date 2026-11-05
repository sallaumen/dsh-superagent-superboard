# API JSON

O board expõe endpoints HTTP em `/api`. As respostas explícitas do
[controller](../lib/agent_board_web/controllers/board_controller.ex) são JSON;
os erros tratados têm um campo `error` com uma mensagem. A interface LiveView
chama o contexto Board diretamente. Os exemplos de entrada abaixo são
ilustrativos: use um repositório e uma tarefa reais ao executar uma requisição.

| Método | Rota | O que faz |
|---|---|---|
| GET | `/api/board?repo=<owner>/<name>` | Estado do board do repositório rastreado |
| GET | `/api/repos` | Lista de repositórios rastreados |
| POST | `/api/repos` | Rastreia um repositório novo |
| POST | `/api/tasks` | Cria uma tarefa (issue no GitHub que menciona o agente) |
| PATCH | `/api/tasks/:id` | Ação sobre uma tarefa: `stop`, `archive` ou `resume` |

## GET /api/board

Parâmetro de query obrigatório: `repo` no formato `owner/name`.

- `200` — o board do repositório (colunas de tarefas por estado).
- `404` — `{"error": "repository not tracked"}` quando o repositório não está rastreado.

## GET /api/repos

- `200` — lista de repositórios rastreados.

## POST /api/repos

Corpo ilustrativo: `{"owner": "example", "name": "project"}`.

- `201` — objeto com `id` (inteiro), `owner` e `name` (strings) do repositório criado.
- `400` — `{"error": "invalid"}` quando a criação não é válida.

## POST /api/tasks

Corpo ilustrativo: `{"repo": "example/project", "title": "Corrigir link da documentação"}`; `body` opcional (detalhes da issue).

- `201` — objeto com `id` (inteiro local), `number` (inteiro da issue) e `url` (string). A issue menciona o agente automaticamente.
- `400` — `{"error": "a repository and a title are required"}` quando o repositório não está rastreado, o slug é inválido ou o título é vazio; o campo `error` contém os erros do changeset quando essa validação falha.
- Efeito real: abre uma issue no GitHub do repositório rastreado.

## PATCH /api/tasks/:id

Corpo: `{"action": "stop"}`. O valor de `action` também pode ser `"archive"` ou `"resume"`; envie uma ação por requisição.

- `200` — `{"ok": true}`.
- `404` — `{"error": "task not found"}` para tarefa inexistente ou ação desconhecida.
- Efeitos reais: `stop` fecha a issue e marca a flag de parada; `archive` arquiva a tarefa; `resume` limpa as flags de parada/arquivamento e volta a tarefa para `queued` localmente. Não reabre a issue no GitHub (ver [Board.resume_task/1](../lib/agent_board/board.ex)).

## Contrato e limites

- O pipeline `:api` aceita apenas JSON — **não há autenticação**; a API é destinada ao próprio board e aos testes. Qualquer uso exposto exigiria um plug de auth antes.
- O cliente GitHub é injetável via `Application.get_env(:agent_board, :github_client)`, o que permite testar os endpoints sem rede (ver `test/agent_board_web/controllers/board_controller_test.exs`).
- O formato dos erros tratados acima não garante um contrato JSON para qualquer exceção. O cliente GitHub pode levantar uma exceção, que o contexto converte em erro; os endpoints ainda podem falhar ao consumir esse resultado. Não presuma que toda falha de rede corresponde ao status de validação documentado.

## Voice (ElevenLabs)

| Método | Rota | O que faz |
|---|---|---|
| GET | `/api/voice/status` | O que está configurado (sem a chave) |
| GET | `/api/voice/voices` | As vozes da conta, para o seletor |
| PUT | `/api/voice/settings` | Salva a voz e o modelo escolhidos (vazio limpa) |
| GET/POST | `/api/voice/speech?text=...` | O áudio falado (mp3) |
| POST | `/api/voice/transcribe` | O corpo de áudio transcrito (JSON) |

### GET /api/voice/status

- `200` — `{"configured": true|false, "status": "logged_in"|"not_configured", "voice_id": "...", "voice_source": "environment"|"saved"|"default", "tts_model": "...", "tts_source": "environment"|"saved"|"default", "stt_model": "..."}`. Nunca expõe a chave. Os campos `*_source` dizem de onde vem cada escolha: a variável de ambiente, a escolha salva na UI ou o padrão.

### GET /api/voice/voices

- `200` — `{"voices": [{"id": "...", "name": "..."}]}` — as vozes da conta.
- Erros seguem o mesmo mapa do speech (401/429/502/503).

### PUT /api/voice/settings

Corpo: `{"voice_id": "..."}` e/ou `{"tts_model": "..."}`. `voice_id` vazio ou em branco limpa a escolha (volta ao padrão); `tts_model` precisa ser um dos modelos oferecidos (`eleven_flash_v2_5`, `eleven_v4`, `eleven_multilingual_v2`).

- `200` — `{"voice_id": "...", "voice_source": "saved"|"default", "tts_model": "...", "tts_source": "saved"|"default"}`. As escolhas persistem na tabela `settings` e valem na hora; `ELEVENLABS_VOICE_ID` / `ELEVENLABS_TTS_MODEL` no ambiente continuam com prioridade.
- `400` — `{"error": "a valid voice id is required"}` para id maior que 64 caracteres; `{"error": "an offered TTS model is required"}` para modelo fora do catálogo.

### GET/POST /api/voice/speech

Parâmetro: `text` (query no GET, corpo JSON `{"text": "..."}` no POST); `voice` opcional escolhe a voz na requisição (o seletor da UI usa isso para o preview). A síntese pede `optimize_streaming_latency=3` para o primeiro byte chegar rápido.

- `200` — os bytes de áudio em `audio/mpeg` (mp3 44.1kHz 128kbps).
- `400` — `{"error": "a text is required"}` sem texto; `{"error": "the text is too long for one request"}` acima de 5000 caracteres; `{"error": "a valid voice id is required"}` para um `voice` que não tem forma de id.
- `401` — `{"error": "ElevenLabs rejected the key"}`.
- `429` — `{"error": "ElevenLabs usage limit reached"}`.
- `503` — `{"error": "voice not configured"}` sem chave (`ELEVENLABS_API_KEY`).

### POST /api/voice/transcribe

Corpo: os bytes de áudio crus (content-type `audio/*`); query opcional: `language` (código ISO 639, ex.: `pt`) e `filename`.

- `200` — `{"text": "...", "language_code": "...", "language_probability": <0-1>, "audio_duration_secs": <segundos>}`.
- `400` — `{"error": "an audio body is required"}` sem corpo.
- `413` — `{"error": "the audio is too large"}` acima do limite (10MB por padrão, configurável via `:voice_audio_max_bytes`).
- Erros da ElevenLabs seguem o mesmo mapa do speech (401/429/502/503).

### Contrato

- O cliente ElevenLabs é injetável via `Application.get_env(:agent_board, :elevenlabs_client)`; os testes usam `Req.Test` sem rede (ver `test/agent_board_web/controllers/voice_controller_test.exs`).
- A chave nunca sai do servidor: estes endpoints respondem com áudio ou transcrição, não com a chave.
- Falhas da ElevenLabs não viram corpo de resposta: o cliente retorna `{:error, reason}` (`:not_configured`, `:auth_expired`, `:usage_limit`, `{:http, status}`), nunca levanta.
