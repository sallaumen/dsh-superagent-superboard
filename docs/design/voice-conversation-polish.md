# Conversa por voz: passe visual

## Direção

- Produto: um instrumento local para conversar com o agente sobre trabalho real, sem esconder o estado da tarefa ou da gravação.
- Caráter: calmo e direto; a superfície flutua com profundidade sutil, sem molduras decorativas.
- Mundo visual: papel quente do Agent Board, Plex Sans para leitura, cores `you`/`agent`/`halt` apenas para significado.
- Momentos importantes: saber se o board ouve ou fala e encontrar a ação de enviar, cancelar ou interromper.
- Detalhe próprio: a barra de atividade responde ao estado real da mídia; o texto mantém o significado mesmo com movimento reduzido.

## Hierarquia observada antes da edição

| Bloco | Peso atual e problema | Peso desejado |
|---|---|---|
| Faixa flutuante | Moldura colorida e gráfico alto lideram; estado repetido no rótulo e título | Título do estado e ação lideram; origem da voz é secundária; barra compacta é apoio |
| Janela da conversa | Caixa branca com várias bordas semelhantes | Superfície única, leve e claramente separada do board por profundidade |
| Mensagens | Bolhas grandes e retangulares parecem cartões | Mensagens legíveis, com alinhamento e curvas distintos para dono e agente |
| Campo e envio | Dois controles isolados com contornos fortes | Uma área de composição simples com ação reconhecível |
| Falar e explicação | Botão e texto competem com o histórico | Ação de falar visível, explicação de apoio |
| Ajuda e bastidores | Duas caixas contornadas adicionais | Linhas discretas, abertas somente quando solicitadas ou quando há problema |

## Estados e limites

- `permission`, `listening`, `transcribing`, `thinking`, `generating`, `speaking`, `complete` e `error` continuam com título, detalhe e ação explícitos. A cor nunca é o único sinal.
- A barra acompanha o nível medido enquanto o microfone ouve; a fala pode animá-la apenas enquanto a reprodução está ativa. Movimento reduzido preserva texto e botão.
- A faixa não toma foco nem intercepta o diálogo inteiro. O teclado mantém foco visível na ação.
- A janela preserva histórico, campo de texto, confirmação de ações, catálogo e bastidores. O conteúdo longo deve rolar sem cortar ações no celular.
- O visual segue [DESIGN.md](redesign/DESIGN.md) e [ui-motion.md](../ui-motion.md). “Apple-like” aqui significa proporção compacta, material leve e detalhes precisos dentro da identidade local; não copia ícones ou cores de outro produto.
