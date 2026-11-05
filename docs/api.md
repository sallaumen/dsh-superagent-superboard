# API JSON

O board expõe uma API JSON em `/api` usada pela própria interface e pelos testes. Todas as respostas são JSON; erros seguem o formato `{"error": "..."}`.

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

Corpo: `{"owner": "...", "name": "..."}`.

- `201` — `{"id": <id>, "owner": "...", "name": "..."}`.
- `400` — `{"error": "invalid"}` quando a criação não é válida.

## POST /api/tasks

Corpo: `{"repo": "<owner>/<name>", "title": "..."}`; `body` opcional (detalhes da issue).

- `201` — `{"id": <id>, "number": <número da issue>, "url": "..."}`. A issue menciona o agente automaticamente.
- `400` — `{"error": "a repository and a title are required"}` quando o repositório não está rastreado, o slug é inválido ou o título é vazio; `{"error": "..."}` com os erros do changeset nos demais casos.
- Efeito real: abre uma issue no GitHub do repositório rastreado.

## PATCH /api/tasks/:id

Corpo: `{"action": "stop" | "archive" | "resume"}`.

- `200` — `{"ok": true}`.
- `404` — `{"error": "task not found"}` para tarefa inexistente ou ação desconhecida.
- Efeitos reais: `stop` fecha a issue e marca a flag de parada; `archive` arquiva a tarefa; `resume` reabre a execução.

## Contrato e limites

- O pipeline `:api` aceita apenas JSON — **não há autenticação**; a API é destinada ao próprio board e aos testes. Qualquer uso exposto exigiria um plug de auth antes.
- O cliente GitHub é injetável via `Application.get_env(:agent_board, :github_client)`, o que permite testar os endpoints sem rede (ver `test/agent_board_web/controllers/board_controller_test.exs`).
- Falhas de rede do GitHub não se transformam em corpo de resposta: a chamada levanta (`GitHub HTTP <status>` ou `GitHub rate limited...`), conforme as regras em AGENTS.md.
