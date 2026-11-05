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
