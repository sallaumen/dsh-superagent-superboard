# Movimento da interface

Contrato do movimento do board: o que anima, com que curva e duração, e o que
nunca anima. A prática compartilhada vive no Elixir Agent Kit (`motion-design` e
`MOTION.md`, via [.elixir-agent-kit/START.md](../.elixir-agent-kit/START.md)); este
documento guarda apenas as decisões deste produto.

Vídeo renderizado, motion graphics e apresentações não seguem este contrato: usam
a skill externa `motion-designer` (motion-kit, MIT) apontada pelo guia de
roteamento do kit.

## Regra

Movimento responde a uma mudança de estado. Ele explica de onde veio uma
superfície nova, confirma que uma entrada foi recebida e mostra que algo saiu.
Nunca bloqueia uma ação, nunca reanima dados transmitidos e nunca sugere trabalho
que não aconteceu.

O board é um instrumento operacional: o registro é técnico e editorial — preciso,
curto, sem espetáculo. No máximo um momento expressivo por tela, e nenhum efeito
de vitrine.

## Tokens

Durações e curvas existem em um só lugar: no bloco `:root` de
[`assets/css/app.css`](../assets/css/app.css). Componentes usam o token, não o
número.

| Token | Valor | Uso |
|---|---|---|
| `--motion-feedback` | 110 ms | Cor de hover, foco e estado de botão e link |
| `--motion-inplace` | 160 ms | Mudança no lugar, como a rotação de um chevron |
| `--motion-enter` | 200 ms | Entrada de superfície nova: painel, menu, aviso |
| `--motion-notice` | 600 ms | Valor que mudou no lugar: a tinta vai de `--agent` a `--ink` |
| `--ease-standard` | `cubic-bezier(0.2, 0, 0.38, 0.9)` | Utilidade (Carbon productive standard) |
| `--ease-enter` | `cubic-bezier(0.05, 0.7, 0.1, 1)` | Entrada que importa (Material 3 emphasized decelerate) |

Saídas são corte imediato. Quando existir uma saída animada, ela será mais curta
que a entrada e acelerará para fora; o token será criado quando houver o caso,
não antes.

## O que se move

| Mudança | Tratamento | Superfície |
|---|---|---|
| Abrir painel ou diálogo | 200 ms, opacidade + 6 px + escala 0.995, `--ease-enter` | `.board-dialog[open]` |
| Abrir o menu de configurações | 160 ms, opacidade + 4 px para cima, `--ease-enter` | `.board-settings-body` |
| Aviso temporário (toast) | 200 ms, opacidade + 4 px, `--ease-enter` | `.toast .alert` |
| Hover, foco e estado de botão/link | 110 ms de fundo e borda, `--ease-standard` | `button, a` |
| Chevron de configurações e de seção | 160 ms de rotação; o estado continua legível sem movimento | `.settings-chevron`, `.settings-fold-chevron` |
| Ponto de atenção e barras de voz | loop lento apenas sob `no-preference`; comunica estado real, não decoração | keyframes `attention-breathe` e `voice-flow` |
| Valor da vazão que mudou | 600 ms de cor, `--agent` → `--ink`, `--ease-standard`; o hook `Throughput` compara o valor anterior e só então aplica `.is-changed`, então um broadcast sem mudança não move nada; a barra nova do sparkline simplesmente aparece | `.ab-flow__value.is-changed` |

## O que não se move

- Cards e linhas que chegam de sync, stream ou poll: o nó novo aparece, sem repetir
  uma entrada. A entrada pertence à superfície, não ao dado.
- Reconexão, refresh periódico, troca de repositório e atualização de contadores.
- Texto de conteúdo: aparece; não desliza, não desfoca e não digita (exceto quando
  o produto literalmente transcreve fala ou escrita).
- Nada de blur-in, fade-up em tudo, shimmer, brilho à deriva ou card flutuante.
- Nenhuma animação atrasa submit, clique, navegação ou leitura.

## Reduced motion

Sob `prefers-reduced-motion: reduce`, animações e transições são desligadas no
bloco global. O estado continua legível: painel e menu abrem na hora, o chevron
gira na hora, o aviso aparece, e o feedback de carregamento continua textual e
visual. Remova o movimento, nunca o feedback.

## Como validar

1. Rode `make frontend` para gerar os assets (o CSS não tem etapa separada).
2. No browser, abra um painel, o menu de configurações e um aviso; confira as
   curvas e durações no painel Animations do DevTools ou em um trace.
3. Emule `prefers-reduced-motion: reduce` e repita: nada anima e os estados
   continuam claros.
4. Repita clique, submit com falha e reconexão: a animação não enfileira, não
   bloqueia e não reanima a lista.
5. Registre o que observou e o que não foi observado. Captura de tela não prova
   movimento nem interação.

## Manutenção

Mudou uma duração ou curva? Atualize o token, a tabela acima e a verificação no
browser, na mesma mudança. Se a melhoria for reutilizável, proponha no kit
([política de evolução](agent/practices.md)); regras e tokens deste board
permanecem locais.
