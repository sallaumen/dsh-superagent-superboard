# Agent Board — DESIGN.md

Base: o design system **Agent Board** (tokens, voz, glifos) continua sendo a fonte da verdade. Este arquivo é o
delta para o board atual e a ponte para LiveView + HEEx + Tailwind/daisyUI. Sem bibliotecas novas.

## 1. O que muda em relação ao board atual

| Hoje | Passa a ser | Por quê |
|---|---|---|
| Cinza frio, preto puro | `paper` quente nos dois temas | Calmo por horas; o DS já decidiu isso |
| 8 tiles de vazão em caixas, no meio da tela | Uma faixa de 8 células divididas por fio, **abaixo das raias** | Vazão é telemetria; a decisão são as raias |
| "Precisa de você" no fim da página (y≈750 a 1920) | Logo abaixo de "Agora", na 1ª coluna, acima da dobra | É a única raia que pede ação sua |
| Objetivos em duas caixas empilhadas | Linhas com fio, barra de 4 px, contagem mono à direita; concluído recua para uma linha `ink-muted` | Menos caixa, mesma informação |
| "SUPERAGENTES" em caixa alta + "Superagentes DeepSeek" repetido | Um título em caixa normal | Regra do DS: sem maiúsculas espaçadas |
| Cards de agente dentro de modal (caixa dentro de caixa) | Tabela: uma linha por projeto | Comparar 2 projetos lado a lado; ações alinhadas |
| "Remover" colado em "Parar" | "Arquivar" no menu ⋯, longe de Pausar/Parar | Destrutivo nunca ao lado do comum |
| "ligado" duas vezes (selo + desejado) | "Ligado · como desejado"; divergência vira telha: "Parado · desejado ligado" | Mostrar só o que informa |
| "Parar / Arquivar" como links coloridos no inspector | Botões; Parar em contorno telha com confirmação inline | Alvo de 32–44 px, foco visível |
| Deltas "−7", "+13" soltos | Mesmos números + "comparado com a hora anterior" no cabeçalho da faixa | Delta sem referência é ruído |

## 2. Tokens

Copie para `assets/css/app.css`. Escuro é `[data-theme="dark"]`; claro é o padrão.

```css
:root {
  --paper:#f6f4ef; --paper-sunk:#eeebe4; --surface:#fdfcf9; --surface-raised:#ffffff;
  --line:#e3ded4; --line-strong:#8a8275;
  --ink:#1f1d1a; --ink-muted:#5c564d; --ink-faint:#6f685e;
  --agent:#2c6a4d; --agent-wash:#e2eee6; --on-agent:#ffffff;
  --you:#2f4f9e;   --you-wash:#e7ecf8;   --on-you:#ffffff;
  --halt:#a8401a;  --halt-wash:#f8e7dd;  --on-halt:#ffffff;
  --stale:#7f5a08; --stale-wash:#f5edd8;
  --focus-ring:var(--you);
  --shadow-layer:0 1px 2px rgba(31,29,26,.06),0 8px 24px rgba(31,29,26,.08);
  --font-sans:"IBM Plex Sans",ui-sans-serif,system-ui,sans-serif;
  --font-mono:"IBM Plex Mono",ui-monospace,"SF Mono",Menlo,monospace;
}
[data-theme="dark"] {
  --paper:#171614; --paper-sunk:#121110; --surface:#201e1b; --surface-raised:#292723;
  --line:#34312c; --line-strong:#7d756a;
  --ink:#ece8e1; --ink-muted:#aaa398; --ink-faint:#958e83;
  --agent:#7cc29d; --agent-wash:#1d2c24; --on-agent:#0e1d15;
  --you:#a3b7ef;   --you-wash:#1e2538;   --on-you:#111a33;
  --halt:#f09670;  --halt-wash:#36211a;  --on-halt:#2a130b;
  --stale:#dcb15e; --stale-wash:#2d2616;
  --shadow-layer:0 1px 2px rgba(0,0,0,.4),0 12px 32px rgba(0,0,0,.45);
}
```

`--on-halt` é novo (botão de confirmação destrutiva preenchido). Fio de divisão dentro de `agent-wash`:
`#2b3f33` escuro / `#c9dccf` claro.

Tailwind (`tailwind.config.js` → `theme.extend`): `colors: { paper:'var(--paper)', 'paper-sunk':'var(--paper-sunk)', surface:'var(--surface)', raised:'var(--surface-raised)', line:'var(--line)', 'line-strong':'var(--line-strong)', ink:'var(--ink)', muted:'var(--ink-muted)', faint:'var(--ink-faint)', agent:'var(--agent)', 'agent-wash':'var(--agent-wash)', you:'var(--you)', 'you-wash':'var(--you-wash)', halt:'var(--halt)', 'halt-wash':'var(--halt-wash)', stale:'var(--stale)', 'stale-wash':'var(--stale-wash)' }`.
daisyUI: mapeie no tema da versão instalada `primary→you`, `success→agent`, `error→halt`, `warning→stale`,
`base-100→paper`, `base-200→paper-sunk`, `base-300→line`, `base-content→ink`. Use daisyUI só para
comportamento (`dropdown`, `modal`, `tabs`, `toggle`); o visual vem dos tokens.

### Tipo (Plex Sans para leitura, Plex Mono só para dado de máquina, sempre `tabular-nums`)

| Nome | Tamanho/linha | Peso | Uso |
|---|---|---|---|
| display | 26/32 | 600, −0.01em | nome do repositório, uma vez por tela |
| title | 16/22 | 600 | seção, painel |
| task | 14.5/21 | 500 | título de tarefa em lista |
| body | 14/21 | 400 | conversa, resumo |
| meta | 12.5/18 | 400 | motivo, metadado |
| label | 12/16 | 600 | rótulo, contagem — caixa normal |
| data | 12.5/18 mono | 450 | hora, duração, custo, caminho |
| data-lg | 22/28 mono | 400 | valor da célula de vazão (novo) |
| data-small | 11.5/16 mono | 450 | #número, kbd |

### Espaço e forma

`space-1..8` = 2, 4, 8, 12, 16, 24, 40, 64 px. Raio: 6 controles · 10 cartões de atenção e linha em foco ·
16 painel, composer, faixa Agora · 999 farol e filtros. Sombra só no que flutua.

## 3. Grade e densidade

| Largura | Estrutura |
|---|---|
| 390 | Sem trilho (repositório vira seletor no topo). Uma coluna: resumo → Agora → Precisa de você → Fila. Mesclados, Vazão e Resumo do dia viram `<details>` de uma linha. Barra fixa embaixo: Novo pedido + voz (48 px). Gutter 16. |
| 768 | Trilho recolhe para 56 px (ícone + marcas). Uma coluna de raias; Mesclados abaixo. Inspector ocupa a tela. |
| 1366 | Trilho 224. Raias em 2 colunas `3fr 2fr`: [Agora, Precisa, Fila] · [Mesclados, Vazão 2×2]. Inspector flutua (abaixo de 1240 px de conteúdo). |
| 1920 | Contexto em `7fr 5fr` (objetivos · resumo do dia). Raias em 3 colunas `5fr 4fr 3fr`: [Agora + Precisa] · [Fila] · [Mesclados]. Vazão em faixa de 8 células abaixo. Inspector 440 px empurra o conteúdo. |
| 2560 | Mesmo layout de 1920 com gutter 48 e inspector 520. **Ocioso**: as quatro raias colapsam numa linha só; abaixo, histórico de 7 dias em 7 colunas e a faixa de vazão mostrando 24 h/7 d. Volta às raias quando algo entra. |

Largura de leitura: texto corrido (resumo, conversa, motivos) ≤ 760 px / ~80 caracteres, mesmo em 2560.
Gaps: 40 entre colunas e seções, 32 entre blocos de uma coluna, 12 entre título de seção e conteúdo.
Linha de lista: 10–12 px vertical; alvo mínimo 32 px no desktop, 44 px no toque.

## 4. Componentes (regras curtas)

- **Farol**: pílula colada ao nome do repositório. Só "Ao vivo" anima. Âmbar para dado velho; nunca vermelho.
- **Faixa Agora**: `agent-wash`, raio 16. Card de execução = status + #id + executor · título · passo real em
  mono `agent` · fases (✓ feito, ● atual, ○ por vir). Falha em nova tentativa: glifo ■ telha + "tentativa n de m" +
  contagem regressiva. Silêncio: glifo hachurado + "sem saída há N min" e também entra em Precisa de você.
- **Item de atenção**: `surface` + `line`, raio 10. Linha 1: glifo ◆/■ + tipo + #id + idade (+ **novo**).
  Linha 2: título. Linha 3: motivo com causa. Uma ação primária à direita. Ordem: CI na main → bloqueio →
  revisão → pergunta → silêncio. Separador "antes da sua última visita".
- **Linha de fila**: número · ○ · #id + título · idade. Selecionada = `you-wash` raio 10. Marcas de texto
  "possível repetida" (âmbar) e "dividida" (muted). Filtros em pílula com `aria-pressed`.
- **Linha de merge**: ✓ · #id + título · "CI ✓/?/falhou · revisão · hora". CI falho troca ✓ por ■ telha.
- **Célula de vazão**: rótulo · valor data-lg + unidade + delta · sparkline 20 px 1.5 px traço `ink-muted` ·
  24 h/7 d. Quatro verdades: medido (sem marca), estimado ("≥" + frase), desconhecido ("?" + glifo tracejado +
  motivo), sem dados ("—"). Nunca 0 para o desconhecido.
- **Inspector**: cabeçalho (status, título, #id · idade · tipo · tamanho · link), ações em botões
  (Perguntar, Tentar de novo, Parar execução em telha, Arquivar discreto), confirmação inline em `halt-wash`
  com a frase e dois botões nomeados ("Parar execução" / "Continuar rodando"). Abas com contagem; `1–5` troca.
  Custo por executor, nunca somado. Despacho: executor em radio-card com sugestão e motivo, teto, tempo,
  saldo do teto mensal, botão nomeado com o executor.
- **Composer**: diálogo `surface-raised` raio 16, etapas Pedido · Revisar · Recibo. Executor em 3 radio-cards
  (sugestão, motivo, custo esperado na moeda dele). Split em linhas com checkbox, tipo e tamanho (P/M/G);
  possível repetida vem desmarcada. Rodapé = frase de confirmação com números + "Criar N tarefas". Recibo:
  criadas · já estavam na fila · falhas com motivo e "Tentar de novo".
- **Superagentes**: tabela (Projeto + state dir · Estado · Workers stepper · Profile · porta · Última leitura ·
  Pausar/Parar/⋯). "Adicionar projeto" é formulário inline com frase de revisão e "Adicionar e iniciar".
- **Voz**: histórico em bolhas (`you-wash` você, `agent-wash` board); confirmação falada em `halt-wash` com
  botões; "Bastidores" como lista de etapas com tempo; "O que posso pedir" agrupado; gasto de voz do dia vs teto.
- **Configurações**: diálogo com navegação lateral; seções na ordem do menu atual; salvar explícito.
- **Hoje**: uma lista; repositório como coluna fixa de 120 px; legenda de glifos no rodapé.

## 5. Sincronia

| | Ao vivo | Atrasado | Reconectando | Sem conexão | Sem dados |
|---|---|---|---|---|---|
| Farol | ● respira | ○ âmbar + "dados de HH:MM · há N" | ◌ âmbar tracejado + "tentativa n" | hachurado + `stale-wash` | ◌ tracejado neutro |
| Relógios | andam | andam | param | "visto às" | — |
| Contagens | exatas | exatas | exatas | "≥" | — |
| Idades | relativas | relativas | relativas | absolutas | — |
| Faixa topo | — | — | — | sim + "Tentar agora" | — |
| Card Agora | normal | normal | normal | hachurado, borda tracejada | vazio "—" |

Ao reconectar: um toast "Reconectado. N mudanças desde HH:MM." + "Mostrar" (marca **novo**). Some em 8 s ou Esc.

## 6. Movimento

| Anima | Como |
|---|---|
| Ponto do agente | opacidade 1 → .35, 2.4 s, só com sincronia ao vivo |
| Camadas (inspector, composer, menus, toast) | entrada 180–220 ms, `translateY(4px)` + opacidade, `cubic-bezier(.2,0,0,1)`; saída 120 ms |
| Troca de estado de um item (fila → rodando → mesclado) | cor e glifo trocam em 150 ms; a linha não se move sozinha |
| Barra de objetivo | largura em 300 ms quando muda por ação sua |

**Não anima**: dado que chega por broadcast (PubSub) — troca o texto no lugar, sem fade, sem contagem
progressiva; reordenação da fila; sparkline; skeleton (estático, sem shimmer); farol fora de "Ao vivo".
Nada bloqueia ação: botões respondem durante qualquer transição.
`prefers-reduced-motion: reduce` → todas as durações 0 e o ponto fica parado; o feedback continua pelo texto
(o farol diz "Ao vivo", o botão diz "Parando…").

LiveView: `phx-mounted`/`JS.transition` só nas camadas; atualizações de stream sem `phx-update` animado.

## 7. Acessibilidade

- Texto ≥ 4.5:1 em todos os fundos (tokens já passam); bordas de controle `line-strong` ≥ 3:1.
- Um anel de foco: 2 px `focus-ring`, afastado 2 px. Ordem de tab: trilho → topo → contexto → Agora →
  Precisa → Fila → Mesclados → Vazão. `J/K` percorre tarefas na ordem da tela, `Enter` abre, `Esc` fecha e
  devolve o foco.
- Estado nunca só por cor: glifo + palavra. `agent` e `halt` têm luminosidade próxima.
- Botões de ícone com `aria-label`; gráficos com `role="img"` e `aria-label` com os números; faixa de dados
  parados com `role="status"`; confirmações com `role="alertdialog"`.
- Atalhos de letra não disparam dentro de campos.

## 8. Copy

Frases curtas, ativas, caixa normal. Erro = causa + recuperação ("Não lemos os PRs. O token do GitHub expirou.").
Confirmação repete o objeto e a consequência ("Parar a execução de #116? A nova tentativa agendada é cancelada.").
Botões nomeiam a ação ("Parar execução", "Criar 7 tarefas"), nunca "OK"/"Sim".

## 9. Hipóteses (fora do escopo atual, marcadas)

1. **hipótese** — Agrupar a Fila por objetivo quando há um objetivo aberto (hoje "0 de 13" e "13 na fila" não se ligam visualmente).
2. **hipótese** — O inspector tem 5 abas no produto (Conversa, Atividade, Chamadas de IA, Execuções, PR) e 4 no brief; decidir se Chamadas de IA entra em Execuções.
3. **hipótese** — Pedidos e respostas escritos sem conexão ficam guardados e saem ao reconectar. Hoje não sei o comportamento; desenhei sem prometer.
4. **hipótese** — Cota do Codex fora do teto em US$ nas Configurações (o brief lista tetos sem dizer por executor).
5. **hipótese** — Contexto de "silêncio de execução": limiar sugerido 10 min sem saída.
