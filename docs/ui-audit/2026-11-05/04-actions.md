# Auditoria: ações e feedback

> **Registro histórico — 5 de novembro de 2026.** Contagens, capturas e estados
> descrevem as revisões identificadas neste documento, não o produto atual.
> Consulte o [índice e a sequência da auditoria](README.md).

Base `67029d2` (#161). Fechamento da auditoria em 05/11/2026.

| Severidade | Região | Evidência antes | Correção |
|---|---|---|---|
| P1 | Create / flash | `board_live.ex` no baseline, linhas 133–135: resultado de `Board.create_task` descartado antes de anunciar “Task created”. [Fixture antes](baseline-fixture.png) também mostra o mesmo erro duas vezes. | Tratar sucesso/erro; erro aparece uma vez no flash compartilhado, com orientação. Testes com GitHub simulado cobrem 422 e sucesso. [Depois](actions-after-fixture.png). |
| P1 | Conversa / troca de repo | `load/2` carregava um repo novo sem limpar `conversation`, `comments` ou `intake`; `handle_info` não recarregava comentários da conversa. | Limpar o contexto na troca e atualizar a conversa em broadcasts. [Open depois](actions-conversation.png), [outro repo vazio](actions-empty.png). |
| P2 | Split / IA indisponível | [Antes](layout-after-1366.png): Split habilitado com `not_configured`; sem feedback próprio de carregamento. | Desabilitar com explicação, anunciar “Splitting…” durante submit, atualizar a lista de chamadas ao concluir. [Depois](actions-after.png). |
| P2 | AI panel | `AI.recent/1` é global; `logged_in` só verifica configuração; rehearsal também dizia logged_in. Lista vazia não explicada. | Mostrar “all repositories”, janela recente, vazio explícito, “configured · connection not verified” e “rehearsal · local fixtures”. Sem alegação de autenticação validada. |
| P2 | Speak / Dictate | `assets/js/app.js` retornava silenciosamente quando a API não existia. “Speak” na conversa falava o board, não a conversa. | Região de feedback e rótulo “Speak board status”; erros/indisponibilidade anunciados. [Speak](actions-speak.png), [API ausente](actions-speech-unavailable.png). |
| P2 | Stop / Archive | `board_live.ex` tinha botões sem estado em trânsito nem explicação do efeito. | `Stopping…`/`Archiving…`, bloqueio em trânsito e title explicando fechar issue versus ocultar no board. Sem acioná-los em tarefas reais. |

Verificação interativa extra: servidor temporário `MIX_ENV=test` em `localhost:4005`,
com fixtures em uma única transação Ecto Sandbox (rollback no encerramento).
Open pelo teclado focou `conversation-title`; Close devolveu foco ao Open original;
trocar repositório removeu a conversa. Nenhuma criação, Stop, Archive ou envio de
mensagem foi acionado no navegador. Speak foi capturado por um substituto silencioso
da API de áudio; texto recebido: “1 running and 1 blocked”. Microfone não foi aberto.
Uma tentativa inicial pelo host 127.0.0.1 foi rejeitada pelo check_origin do ambiente
de testes; usar localhost resolveu. Não houve mudança da proteção de origem.

Gate final: `scripts/ci-local.sh all` verde, incluindo `MIX_ENV=test mix gate`
(158 testes, zero falhas), `scripts/check_assets.sh`, `mix assets.build`, assets.deploy,
validador e 20 testes da biblioteca. CI bloqueada por billing conforme informado;
a evidência local é suficiente segundo PIPELINES.md. Nenhum PR foi mesclado.

## Matriz final de cobertura

| Área | Resultado | Evidência / limite |
|---|---|---|
| 1366×768, claro e escuro | Verificado | [claro](final-light-1366.png), [escuro](final-dark-1366.png); sem overflow, conexão ativa |
| 3440×1440, claro e escuro | Verificado | [claro](final-light-3440.png), [escuro](final-dark-3440.png); sem overflow |
| 375×812 extra | Verificado | [claro](final-light-375.png), [escuro](final-dark-375.png); scrollWidth=375 |
| Tema / persistência / sistema / teclado | Verificado | PR #154; alternância real, reload, prefers-color-scheme e foco |
| Contraste | Amostras corrigidas | [medidas](final-contrast.txt): primary 5,38/5,36; textos semânticos sobre base100 entre 5,99 e 7,38 no claro, 6,19 e 7,11 no escuro. Não equivale a certificação integral WCAG. |
| Conexão / reconexão / sync_error | Verificado | PR #161; disconnect/connect + Activity; zero erros no console do app |
| Empty / sem repo / sem comentários | Verificado | Empty e sem comentários no navegador de testes; sem repo coberto por LiveViewTest |
| Flash sucesso/erro | Verificado em testes | Create com respostas simuladas; erro visual por fixture renderizada |
| Loading de ações mutáveis | Verificado por código | phx-disable-with e bloqueio do LiveView; sem submissão real nem chamada paga |
| Split resultado / lista AI | Verificado em testes | Req.Test simula as duas chamadas, exibe proposta e atualiza o histórico; nenhuma tarefa real criada |
| Open / Close / troca repo | Verificado no navegador | Fixtures transacionais; foco, retorno e remoção de contexto |
| Stop / Archive | Código e testes existentes | Board.stop_task/2 e archive_task/1; não executados no navegador |
| Speak | Verificado sem reprodução | Evento real do LiveView recebido por API substituta; som real não avaliado |
| Dictate | Indisponibilidade verificada | Feedback com APIs ausentes; reconhecimento real e permissões de microfone não avaliados |
| Leitor de tela | Não executado | Árvore acessível, nomes, aria-live e teclado inspecionados; nenhum leitor assistivo real usado |

Limite operacional: o sync local de `sallaumen/o_colmex` continua recebendo GitHub HTTP
404. A auditoria corrigiu a sinalização e preservou os dados salvos; não alterou
credenciais/permissões nem tentou corrigir acesso ao repositório.

Os navegadores e servidores temporários da auditoria foram encerrados; o servidor
pré-existente na porta 4002 foi preservado. Capturas identificadas como fixture são
sintéticas, sem dados persistidos ou chamadas externas.
