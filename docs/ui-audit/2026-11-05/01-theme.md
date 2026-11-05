# Auditoria: tema e acessibilidade

Base: `52113d4` (main, incluindo #152). WebKit headless, 05/11/2026.
`mix setup` passou. A porta 4002 pertence ao checkout `/Users/tavano/src/agent_board`;
foi preservada. Este checkout foi servido com `PORT=4003 mix phx.server`.
Dados reais apenas lidos. A página `fixture` é HTML renderizado com structs em memória,
sem inserir tarefas ou chamadas de IA. Não representa uma sessão LiveView conectada.

Direção: console operacional para acompanhar agentes, preservando a tipografia mono,
as cinco colunas e a ênfase em tarefas/bloqueios. Refinar legibilidade, sem redesign.

| Severidade | Região | Evidência antes | Correção |
|---|---|---|---|
| P1 | Contraste | [Claro](baseline-light-1366.png), [formulários](baseline-forms.png). Primary/content: 2,75:1 light, 4,13:1 dark; success/base: 2,31:1 light; error/base: 2,94:1 dark. | Ajustar tokens canônicos, preservando laranja claro e violeta escuro. Primary/content agora 5,38:1 e 5,36:1. Textos secundários usam 75% em vez de 40/60%. |
| P2 | Tema | Nenhum `[data-phx-theme]` renderizado; [cabeçalho](baseline-dark-1366.png). A função existia mas não era chamada. | Controle System/Light/Dark com nomes, `aria-pressed`, persistência e suporte à preferência do sistema. |
| P2 | IA e carregamento | `board_live.ex` usava `text-[#e8a33d]`; `app.js` tinha `#29d` e sombra RGBA. [IA](baseline-mobile-ai.png). | `text-warning` e cor do progresso derivada de `--color-primary`. Cores literais ficam nas definições dos tokens; arte Phoenix não roteada e vendors ficam fora desse escopo. |
| P2 | Teclado/formulários | [Fixture](baseline-fixture.png): campos dependiam de placeholders, foco inconsistente e ações de 25px. | Nomes explícitos para título/detalhes/mensagem, foco compartilhado e controles com altura mínima 44px. |

Depois: [claro](theme-after-light.png), [escuro](theme-after-dark.png),
[fixture](theme-after-fixture.png), [foco de teclado](theme-keyboard-focus.png).

Verificado: clique e teclado nos temas, aria-pressed, reload, System + mudança da mídia
para dark, LiveView conectado e zero erros de console. Contraste calculado com cores
resolvidas pelo canvas do WebKit (sRGB); não é uma certificação de toda combinação.

Gate local: `scripts/ci-local.sh all` (inclui `MIX_ENV=test mix gate`,
`scripts/check_assets.sh`, `mix assets.build`, assets.deploy e biblioteca).
151 testes Elixir, zero falhas. CI indisponível por billing conforme informado;
não esperamos nem redisparamos Actions. Reexecutar workflow_dispatch quando liberado.
