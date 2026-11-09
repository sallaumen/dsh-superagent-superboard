O Agent Board é a mesa de trabalho de quem deixa agentes programando e volta para ver o que mudou. Ele não é um painel de métricas: é uma leitura. A pergunta que cada tela responde, nesta ordem, é **o que o agente está fazendo agora, o que só eu posso destravar, o que mudou desde que saí e quão recente é tudo isso**.

## Princípios

1. **A verdade antes da forma.** Um número só aparece se veio de um dado observado. Dado velho se declara velho (`stale`, hachura, “≥”, “visto às 09:36”); dado desconhecido vira `?` ou “desconhecido”, nunca `0`. Um cronômetro só anda enquanto a sincronia está ao vivo.
2. **Seu trabalho é azul, o do agente é verde, o que travou é telha.** `you` marca tudo o que espera uma decisão sua (revisão, pergunta, seleção, ação primária). `agent` marca o que o agente está fazendo. `halt` marca bloqueio e falha. O que terminou recua para `ink-muted`.
3. **Espaço separa, não caixa.** Seções vivem soltas sobre `paper`, divididas por espaço (`space-7`) e por fios `line`. Só ganham superfície (`surface`) as coisas que pedem uma ação sua. Nada de quatro colunas iguais com vazio dentro.
4. **Ficar na página.** Abrir uma tarefa abre o painel lateral; escrever um pedido abre o composer por cima. A lista continua visível e o foco volta para onde estava ao fechar (`Esc`).
5. **Calmo por horas.** Fundo quente e pouco saturado nos dois temas, um único movimento contínuo (o ponto do agente respirando) e nenhum outro.

## Conteúdo e voz

- Português do Brasil, frases curtas, caixa normal. Rótulos nunca em MAIÚSCULAS espaçadas.
- Diga o motivo, não o estado: “**CI falhou em `gates`** depois do merge. A main está vermelha desde 23:58.” em vez de “CI FAILED: GATES”.
- O resumo do topo é **uma frase**, escrita a partir dos dados desde a sua última visita: “Desde ontem às 22:10 o agente mesclou 3 PRs, os 3 com CI falhando, abriu 1 PR para revisão…”. Cada trecho é um link colorido pelo papel (`you`, `agent`, `halt`).
- Tempo relativo para o que é recente (“há 41 min”), hora absoluta em `data` para o que é registro (“23:41”). Quando a conexão cai, troque para absoluto: “dados de 09:36”.
- Títulos de tarefa como o agente ou você os escreveu; não traduza nem reescreva.
- Sem emoji, sem exclamação, sem “Ops!”.

## Cor

- Fundo da página `paper`; trilho e campos recuados `paper-sunk`; itens acionáveis e o painel `surface`; o que flutua `surface-raised` com `shadow-layer`.
- Texto em `ink`; motivos e metadados em `ink-muted`; carimbos e números de PR em `ink-faint`. Os três passam 4.5:1 sobre todos os fundos e washes nos dois temas.
- Cada papel tem um tom e um wash: `agent`/`agent-wash`, `you`/`you-wash`, `halt`/`halt-wash`, `stale`/`stale-wash`. O tom serve para texto e marcas; o wash é só fundo. Texto sobre preenchimento `you` usa `on-you`, sobre `agent` usa `on-agent` — nunca branco literal.
- `agent` e `halt` têm luminosidade parecida: **nunca** dependa só da cor. Todo estado leva glifo e palavra (veja StatusMark).
- Bordas de controle em `line-strong` (≥3:1). `line` é decorativa.

## Tipografia

- `sans` (IBM Plex Sans) para interface e leitura; `mono` (IBM Plex Mono) só para o que é dado de máquina: horas, durações, tokens, custos, hashes, caminhos, comandos. Mono sempre com `tabular-nums`.
- Escala: `display` uma vez por tela (nome do repositório), `title` para seções e o painel, `task` para títulos em listas, `body` para conversa, `meta` para motivos, `label` para rótulos e contagens, `data`/`data-small` para valores.

## Espaço, forma e camadas

- Página com gutter `space-6` (`space-5` no celular); `space-7` entre seções; `space-4` de padding vertical por linha.
- `radius-sm` para controles, `radius-md` para linhas em foco e cartões de “Precisa de você”, `radius-lg` para o painel, o composer e a faixa “Agora”, `radius-pill` para o farol de sincronia e filtros.
- Sombra só em camada que flutua (`shadow-layer`). Cartões no fluxo usam `line`, não sombra.

## Estrutura da tela

- **Trilho** (224px, `paper-sunk`): repositórios com marcas de atenção — ponto do agente se há algo rodando, `◆ n` esperando você, `■ n` bloqueado ou com CI falhando, `?` se o dado do repositório está velho.
- **Topo**: nome do repositório, o **farol de sincronia** colado nele, e as ações `Dividir pedido` e `Novo pedido` (`N`).
- **Resumo** de uma frase desde a última visita.
- **Coluna principal**, nesta ordem: **Agora** (o passo real do agente) → **Precisa de você** (ordem: CI falhando na main, bloqueios, revisões, perguntas; o que é novo desde a visita vem antes da linha “antes da sua última visita”) → **Fila** (numerada, de cima para baixo, com aviso de repetição).
- **Coluna lateral**: **Mesclados** — sete dias em pontos (um ponto por PR, telha se o CI falhou) e o registro por dia.
- **Painel lateral** (440px; 520px no ultrawide): Conversa, Atividade, Chamadas de IA, PR. Abaixo de ~1240px de largura ele flutua sobre o conteúdo; no celular ocupa a tela.

## Sincronia e honestidade

- O farol tem cinco estados: **Ao vivo** (todas as fontes responderam no último minuto), **Atrasado**, **Reconectando**, **Sem conexão** e **Sem dados ainda**. Clicar abre o detalhe por fonte (GitHub, processo do agente, fila local).
- Sem conexão: faixa `stale-wash` “Mostrando o que sabíamos às HH:MM”, contagens com “≥”, cronômetros parados com “visto às”, o cartão “Agora” hachurado, o trilho com `?`, a área de dados levemente dessaturada.
- Ao reconectar: um aviso único no canto (“Reconectado. 3 mudanças desde 09:36.”) com `Mostrar`, que destaca essas mudanças com a marca **novo**.
- Custo ou tokens faltando: mostre `—` e totalize como mínimo (“≥ $1.52”), dizendo que é mínimo.

## Movimento

- O ponto `agent` respira (2.4s) só enquanto a sincronia está ao vivo. Parado = não sabemos.
- Camadas entram com 180–220ms de subida curta; nada mais anima. `prefers-reduced-motion` desliga tudo.

## Teclado e foco

- `J`/`K` percorre tarefas na ordem da tela, `Enter` abre no painel, `Esc` fecha a camada de cima e devolve o foco, `N` novo pedido, `V` ditar, `1–4` troca a aba do painel, `?` lista os atalhos.
- Anel de foco único: `focus-ring`, 2px sólido, afastado 2px. Passa 3:1 sobre todos os fundos nos dois temas.

## Iconografia

- Estados são glifos geométricos desenhados em CSS: ● rodando, ◆ espera você, ■ bloqueado/falhou, ○ na fila, ✓ mesclado, círculo hachurado dado velho, círculo tracejado desconhecido.
- Ícones de ação são traços de 1.6px em 16×16 (`AgentBoard.ico`). Não há logotipo: o nome é escrito em tipo, com uma marca simples de ponto `agent` sobre `ink`.

## Usando os componentes

`components/bundle.js` expõe `window.AgentBoard` sem React: funções que recebem dados e devolvem HTML (`needsSection`, `nowSection`, `queueSection`, `logSection`, `inspector`, `composer`, `beacon`) e `mount(el, estado)`, que liga teclado, painel e relógio. `AgentBoard.demo` traz os estados de exemplo usados nas telas (`morning`, `working`, `offline`, `reconnected`, `volume`, `empty`). Os formatos de dados estão em `components/index.d.ts`.
