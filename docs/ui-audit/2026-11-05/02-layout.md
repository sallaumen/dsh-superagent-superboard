# Auditoria: densidade, responsividade e leitura

> **Registro histórico — 5 de novembro de 2026.** Contagens, capturas e estados
> descrevem as revisões identificadas neste documento, não o produto atual.
> Consulte o [índice e a sequência da auditoria](README.md).

Continuação de 01-theme; base `80e3ee9` (#154). Mesma direção e restrições.

| Severidade | Região | Evidência antes | Correção |
|---|---|---|---|
| P2 | Colunas e hierarquia | [1366](layout-before-1366.png), [3440](layout-before-3440.png): 30 merges alongam toda a página, deixando quatro colunas praticamente vazias e escondendo ações. | Colunas com rolagem própria (55vh no desktop), cabeçalhos fixos e foco de teclado. Activity em disclosure nativo, com lista limitada e rolável. |
| P2 | Títulos | [Antes](layout-before-1366.png): títulos cortados numa única linha, especialmente na largura de notebook. | Quebra de palavras e título completo; mantidas as cinco colunas. |
| P2 | Mobile / activity / AI | [Antes](baseline-mobile-ai.png), [layout a 375px](layout-before-375.png), [fixture](baseline-fixture-mobile.png): página de 375px tinha scrollWidth 664px; linhas rígidas se sobrepunham. | Grupos de controles coesos, grid adaptável para eventos, IA com wrap, campos encolhíveis. |
| P2 | Open / conversa | [Antes](baseline-fixture.png): conversa abaixo de Activity, Split e AI. | Conversa logo após o board; título recebe foco ao montar, Close restaura o foco de Open. |
| P3 | Vazio | `board_live.ex`: instrução “Track one below” e “four columns” contrariava a tela. | Orientação para o cabeçalho e cinco colunas. |

Depois: [1366×768](layout-after-1366.png), [3440×1440](layout-after-3440.png),
[375×812](layout-after-375.png), [escuro](layout-after-dark.png),
[Activity mobile](layout-after-mobile-activity.png),
[fixture desktop](layout-after-fixture-1366.png), [fixture mobile](layout-after-fixture-375.png).
Capturas full-page usam a largura do viewport; sua altura pode exceder o viewport.

WebKit: scrollWidth igual ao viewport em 1366, 3440 e 375 (incluindo fixture).
Em 1366, altura da página caiu de ~3050 para 930px e Split começa em y≈658.
Disclosure abre por interação nativa; fixtures só verificam apresentação.
A conversa interativa é coberta pelos testes LiveView; nenhum Open existia nos dados
locais reais e nenhuma tarefa foi criada para a auditoria.

Gate: `scripts/ci-local.sh all` verde; 151 testes Elixir, zero falhas; checks de assets,
build/deploy, validador e 20 testes da biblioteca verdes. CI bloqueada por billing;
gate local suficiente conforme PIPELINES.md. Sem merge/deploy.
