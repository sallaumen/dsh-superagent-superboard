# Contexto: Mercado, Indústria, Casa de Máquinas e Amostras

Aplicar com `colmex-base`. Este contexto reúne intenções relatadas, sem afirmar quais conectores ou capacidades já existem.

## Mercado como domínio de oferta real

O objetivo é administrar muitas lojas, marcas e contas em diferentes canais, oferecendo somente combinações que tenham atendimento comprovado no contexto comercial escolhido. Descubra o modelo real de mercado, loja, marca, conta, canal, produto, variante, fornecedor e destino antes de desenhar uma nova UI.

Uma camiseta preta atendida por um fornecedor não comprova atendimento para a camiseta rosa. Considere cor, tamanho, técnica, área de impressão, arte ou versão e demais dimensões que o catálogo realmente utiliza. Preserve o vínculo entre a oferta e o SKU ou capacidade correspondente do fornecedor.

Distinga país do mercado, país de cadastro do fornecedor, origem de fabricação, origem de envio e destino de entrega. Se o produto exigir fabricação local, essa é uma regra adicional explícita; não deduza fabricação local a partir de entrega internacional.

Represente elegibilidade confirmada, bloqueada, pendente, desconhecida ou desatualizada com motivo acionável. Revalide nos pontos em que a decisão importa. Alterar o catálogo não deve reescrever a história de um pedido antigo ou trocar silenciosamente sua variante.

O crescimento para muitas lojas exige isolamento de configuração, credenciais, disponibilidade e publicação. Não crie ofertas em canais externos durante a investigação. O modo jogo deve ensinar a lógica do modo real usando dados e efeitos controlados.

Skills principais: revisar-arquitetura, contratos-e-dados, setup-integracoes, elegibilidade-comercial, metricas-e-custos, migracoes-e-compatibilidade e simulacao-e-producao.

## Setup e operação de fornecedores

O usuário relatou dificuldade de entender o que falta mesmo após configurar uma conta. A interface deve distinguir conta cadastrada, credenciais válidas, permissões suficientes, catálogo sincronizado, variante elegível e operação pronta. “Conectado” sozinho pode esconder várias pendências diferentes.

Descubra todos os fornecedores presentes no código e associe documentação, painel da conta, credenciais, catálogo, regras de impressão, amostras e suporte quando esses destinos existirem. Verifique links oficiais e sua finalidade. Organize metadados reutilizáveis por fornecedor, sem espalhar URLs arbitrárias em componentes. Não invente links para preencher a lista.

Ofereça setup retomável, com próximo passo claro e reutilização dos dados já preenchidos. Separe o que o usuário precisa configurar do que falta implementar no conector. Uma capacidade não suportada pelo fornecedor precisa aparecer de maneira diferente de uma configuração incompleta.

YouDraw é um nome citado pelo usuário. Verifique qual serviço e conector esse nome representa no projeto antes de atribuir APIs, autenticação ou recursos a ele. Um screenshot ou uma descrição de progresso não comprova prontidão do backend.

Skills principais: estados-assincronos, setup-integracoes, seguranca-e-permissoes e alertas-operacionais.

## Amostras e visualização de produto

Ao selecionar um produto, variante e destino, a interface deve revelar automaticamente fornecedores compatíveis e os motivos dos incompatíveis ou ainda desconhecidos. Isso depende de dados e regras reais; evite apresentar todos os fornecedores como opções equivalentes.

Mostre thumbnails e vistas relevantes, como frente e costas, vinculadas à variante e à arte efetivamente escolhidas. Ao trocar a seleção rapidamente, respostas antigas não podem substituir a imagem atual. Diferencie foto do produto, mockup do fornecedor, composição local e ilustração de IA. Uma imagem convincente não comprova que o produto possa ser fabricado.

Separe prévia visual, simulação de pedido e pedido de amostra físico com custo. Informe custo e condições quando conhecidos. A confirmação de uma operação real deve refletir seu efeito e usar a autorização necessária para a compra.

É permitido propor IA para interpretação de erros, orientação, organização de conteúdo ou prévias quando houver valor. A camada precisa ter contrato, origem, limites e tratamento de falhas. A IA não decide por invenção se uma credencial é válida, se um SKU existe ou se um fornecedor pode entregar.

Skills principais: interacoes-diretas, estados-assincronos, setup-integracoes, elegibilidade-comercial, assets-e-imagens e simulacao-e-producao.
