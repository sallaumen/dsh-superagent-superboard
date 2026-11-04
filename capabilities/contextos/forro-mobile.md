# Contexto: projeto de forró, mobile first

Este é um site ou aplicativo com uso principal no celular e uma linguagem mais próxima de um site tradicional. Preserve sua identidade real; não importe abelhas, flores ou metáforas operacionais do Colmex.

## Composição e interação

Busque uma interface elegante, clara e visual, com ações reconhecíveis e boa legibilidade. A referência compartilhada usa uma identidade quente e sóbria, com tons claros e escuros e tipografia de destaque; confirme os tokens atuais antes de alterar a direção. Não transforme essa descrição em uma paleta obrigatória sem avaliar o produto rodando.

Priorize tarefas que a pessoa executa com uma mão: encontrar conteúdo, escolher uma atividade, consultar detalhes e voltar ao ponto de origem. Reduza explicações repetitivas e cartões superdimensionados, preservando informação que permite decidir. Evite cabeçalhos e barras fixas que ocupem a maior parte da altura útil.

Use larguras como 360, 390 e 430 pixels como pontos de inspeção, adaptando a matriz aos dispositivos suportados. Verifique teclado virtual, textos longos, áreas seguras e orientação quando forem relevantes. Desktop e telas largas precisam de composição própria; não basta ampliar os elementos do celular.

## Histórico e retorno

Ao abrir uma modal ou painel que representa um estado de navegação, o comando nativo de voltar deve desfazer primeiro esse estado quando esse for o comportamento adequado. Fechar pelo botão, pelo comando nativo ou pelo gesto suportado precisa manter coerência de histórico, foco e contexto.

Não presuma um lado de gesto comum a todos os celulares. Verifique sistema, navegador e modo de execução efetivos. Emulação de viewport não demonstra comportamento de gesto em aparelho.

Considere modal aberta a partir da lista, acesso direto ao detalhe, recarga com overlay aberto, fechar e reabrir, voltar e avançar. Preserve item, filtros, posição útil e alterações não salvas conforme a tarefa. Evite entradas fantasmas, armadilhas que impeçam sair do site e repetição de efeitos de negócio ao navegar no histórico.

## Fronteiras de trabalho

Home e Estudos podem ser frentes próprias, respeitando os componentes compartilhados e um responsável por alterações transversais. Revise todas as páginas internas do fluxo escolhido, não somente a capa.

Programação, Eventos, Turmas e Escolas devem participar da mesma frente de integração visual e de navegação, mesmo quando Turmas e Escolas estiverem atualmente sob Estudos. Isso não exige mudar automaticamente a navegação principal ou fundir os domínios; exige que relações e transições sejam claras.

Dê uma linguagem comum às listagens, filtros, detalhes e ações, mantendo as diferenças entre evento, turma, escola e programação. Um evento com ocorrência única não é semanticamente igual a uma turma recorrente. Quando existirem, mostre data, horário, fuso, local, vínculo com escola, professor, disponibilidade e inscrição com base nos dados reais.

Não invente calendário, vagas, preço ou recorrência para preencher lacunas visuais. Um vínculo entre turma e escola deve ser navegável e preservar o contexto de origem. Teste como a pessoa descobre uma atividade, avalia se pode participar, executa a ação disponível e volta à programação.

## Evidência esperada

Entregue fluxos antes e depois, screenshots comparáveis dos estados críticos, verificação de navegação e limites de teste em dispositivo real. Diferencie a redução de espaços desperdiçados da redução de informação essencial.

Skills principais: identidade-ui, espaco-e-densidade, ux-e-navegacao, mobile-e-responsividade, mobile-e-responsividade, interacoes-diretas, acessibilidade, design-system e validar-entrega.
