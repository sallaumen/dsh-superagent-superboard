# Prompt — implementar o redesign do Agent Board

Você vai implementar um refinamento visual e de layout do **Agent Board**, o painel local (Phoenix LiveView,
127.0.0.1:4099) que opera o DeepSeek Super Agent e despacha Claude Code e Codex. O design já foi feito; seu
trabalho é levá-lo para o código existente sem quebrar o que funciona.

## Material

Tudo está em `docs/design/redesign/` (descompactado do zip):

- `PROMPT.md` — este arquivo.
- `DESIGN.md` — **leia primeiro.** Tokens CSS (claro/escuro), mapeamento Tailwind/daisyUI, grade por largura,
  regras de cada componente, estados de sincronia, regras de movimento, acessibilidade, copy e hipóteses.
- `BRIEF.md` — o brief original com o mapa funcional do produto. É a referência do que **existe**.
- `design-system/README.md` e `design-system/tokens.json` — o design system Agent Board (fonte da verdade de
  cores, tipo, espaço, voz e glifos).
- `frames/*.dc.html` — os 13 frames do design. São HTML com estilos inline: abra no navegador ou leia o código.
  Ignore `<x-dc>`, `<helmet>`, `support.js` e o `<script type="text/x-dc">` (são do editor de design); o que
  interessa é a marcação e os estilos dentro deles. As cores estão como hex literal; no código use os tokens
  do `DESIGN.md`.
- `renders/*.png` — captura de cada frame, para comparar visualmente.
- `reference/board-atual-1920.png` e `reference/superagentes-atual.png` — como o board está hoje.

Frames: `Main` (board 1920, trabalhando, escuro), `Board1366Offline` (1366, sem conexão, claro),
`Board2560Idle` (2560 ocioso), `Board390` (celular), `Inspector`, `Composer` (dividir pedido), `Superagentes`,
`Voz`, `Configuracoes` (+ atalhos), `Hoje`, `Componentes` (estados de cada peça), `Sincronia`, `Grade`.

## Regras

1. **Os frames são direção, não contrato.** A maior parte deles faz sentido e deve ser seguida. Se algo numa
   tela não fizer sentido diante do código real (um dado que o board não tem, um fluxo que não existe, um
   controle que contradiz o comportamento atual), **ignore essa parte** e siga o restante. Anote o que ignorou
   e por quê.
2. **Limitações do superagent.** O DeepSeek Super Agent pode não expor alguns dados ou ações que aparecem nos
   frames (ex.: passo atual em tempo real, fases, tickets encerrados, escala de workers, estado desejado vs
   real, falha classificada). Se não houver fonte, **não invente**: mostre o estado honesto que o DESIGN.md
   prevê (`?` com motivo, `—`, ou esconda o elemento) ou deixe de fora. Não crie endpoints falsos nem dados
   simulados.
3. **Não invente funcionalidades.** Preserve a estrutura funcional do `BRIEF.md`. Os itens marcados como
   "hipótese" no `DESIGN.md` §9 **não** devem ser implementados agora; apenas liste-os no resumo final se você
   achar que algum é trivial.
4. **Dados de exemplo nos frames são exemplos.** Números de issue, títulos, valores e os títulos de PR do
   `o_colmex` são ilustrativos. Use sempre os dados reais.
5. **Stack.** Phoenix LiveView + HEEx + Tailwind (+ daisyUI só para comportamento: dropdown, modal, tabs,
   toggle). Sem bibliotecas novas de UI, sem React. Componentes de função em `core_components` ou num módulo
   de componentes do board, seguindo as convenções que já existem no projeto.
6. **Honestidade de dado vem antes de estética.** Nunca mostrar `0` para desconhecido; `≥` para mínimos;
   relógios só andam com sincronia ao vivo; idades viram hora absoluta sem conexão.
7. **Movimento.** Só o ponto do agente respira (e só ao vivo) e as camadas entram/saem. Dado que chega por
   PubSub/stream troca no lugar, sem animação. `prefers-reduced-motion` zera tudo.

## Como trabalhar

1. **Explore antes de mexer.** Leia `DESIGN.md`, olhe os renders, depois mapeie o código: layout raiz,
   LiveViews do board/inspector/composer/hoje/superagentes/voz/configurações, componentes, `app.css`,
   `tailwind.config.js`, tema daisyUI atual, testes. Escreva um plano curto (arquivos a tocar, ordem, riscos)
   e o que você já sabe que não vai dar para fazer por limitação de dados.
2. **Fatias pequenas, cada uma verde.** Ordem sugerida, um commit (ou PR) por fatia:
   1. Tokens CSS claro/escuro + Tailwind + fontes IBM Plex; trocar cores literais por tokens. Nada de layout ainda.
   2. Primitivos: StatusMark (glifo + palavra), botões (primário, secundário, discreto, destrutivo,
      desabilitado com motivo), farol de sincronia, kbd, anel de foco único.
   3. Layout do board: trilho, topo, contexto (objetivos + resumo do dia), raias na grade por largura
      (`DESIGN.md` §3), "Precisa de você" logo abaixo de "Agora", Vazão como faixa abaixo das raias.
   4. Estados: vazio, carregando, erro, ocioso (raias colapsam numa linha em telas largas), sem conexão
      (faixa, `≥`, relógios congelados, hachura), reconectado (toast).
   5. Inspector (cabeçalho, ações com confirmação inline, abas, execuções com custo por executor, despacho).
   6. Composer (etapas, executor em radio-cards, revisão do split, frase de confirmação, recibo).
   7. Superagentes (tabela; arquivar no menu ⋯ longe de Pausar/Parar; adicionar projeto inline com revisão).
   8. Voz, Configurações, Atalhos, Hoje.
   9. Celular (390) e 768.
3. **Testes.** Mantenha a suíte verde a cada fatia. Ajuste testes de LiveView que dependem de texto/seletores
   que mudaram; adicione testes para os estados honestos (desconhecido → `?`, sem conexão → `≥`, ocioso) e
   para as confirmações (parar execução, arquivar).
4. **Verifique visualmente.** Rode o app e compare com os renders em 390, 1366, 1920 e 2560, temas claro e
   escuro. Cheque contraste (≥ 4.5:1 no texto), foco visível em tudo que é clicável, ordem de tab, e
   `prefers-reduced-motion`.
5. **Não mude comportamento** (sincronização, despacho, voz, tetos) a não ser que o layout exija; se exigir,
   pare e explique antes.

## Entrega

Ao final, um resumo com: o que foi implementado por fatia; o que ficou de fora e por quê (frame que não fez
sentido, limitação do superagent, falta de dado); hipóteses do §9 que pareceram triviais; e capturas das telas
principais nas larguras acima.
