# Auditoria: saúde e verdade dos dados

Base `7883316` (#158). Dados reais somente lidos; nenhuma escrita em tarefas.

| Severidade | Região | Evidência antes | Correção |
|---|---|---|---|
| P1 | Saúde do sync | [Antes](layout-after-1366.png): “no sync yet” apesar de `sync_error` recorrente. `last_sync/1` procurava apenas `sync` na janela dos 20 eventos. | Consulta dedicada ao último `sync`/`sync_error`; falhas prevalecem sobre sucesso anterior, identificam dados salvos e abrem Activity. Datas com dia e UTC explícito. |
| P1 | Reconexão | [Antes](baseline-disconnected.png): “live” continuava após disconnect. | Estado atualizado pelos eventos de conexão do cliente, sem depender de um novo render do servidor. |
| P2 | Merged / Speak | `Board.board_for/1` limita merges a 30; a UI parecia mostrar total. `Voice.summary/2` ignorava `blocked` e chamava um board só bloqueado de calm. | “latest N” no contador, “recent merges” na fala, bloqueios incluídos. |

Depois: [saúde](health-after.png), [atividade aberta pelo status](health-activity.png),
[desconectado](health-disconnected.png). WebKit confirmou `live → reconnecting → live`
via disconnect/connect do LiveSocket. Dados e chamadas de rede não foram alterados.
Zero erros de console.

Testes adicionados: sync além da janela de 20 eventos, falha posterior ao último
sucesso e resumo de um board somente bloqueado. Gate local `scripts/ci-local.sh all`
verde (154 testes Elixir; assets checks/build/deploy; validador e 20 testes da biblioteca).
CI bloqueada por billing conforme informado; workflow_dispatch após liberação.
