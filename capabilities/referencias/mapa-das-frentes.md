# Mapa das frentes que originaram a biblioteca

Esta tabela relaciona os pedidos anteriores aos arquivos reutilizáveis. Ela não afirma que as melhorias foram implementadas nos produtos. Os nomes específicos ficam nos contextos para que as skills possam ser usadas em outros projetos.

| Frente ou necessidade | Prompt principal | Complementos conforme o problema | Contexto |
|---|---|---|---|
| Consolidar casas e decidir o destino de ideias inacabadas | coordenar-entregas | coordenar-entregas, consolidar-codigo, validar-entrega | colmex-base; seção da casa |
| Arquitetura, módulos e funções públicas ou privadas | revisar-arquitetura | stratified-design, organizar-modulos, contratos-e-dados, migracoes-e-compatibilidade | Stack confirmada no projeto |
| Estudar e aplicar stratified design | stratified-design | revisar-arquitetura, organizar-modulos, estrategia-de-testes | elixir-phoenix-oban, quando pertinente |
| Refinamento do Ateliê, versões, avaliação e imagens | identidade-ui | versoes-e-rastreabilidade, espaco-e-densidade, ux-e-navegacao, mobile-e-responsividade, interacoes-diretas, assets-e-imagens | colmex-casas |
| Prefeitura, pendências e alertas acionáveis | alertas-operacionais | ux-e-navegacao, estados-assincronos, metricas-e-custos | colmex-casas |
| Casa de Máquinas e configuração operacional | setup-integracoes | estados-assincronos, orquestracao-ias, notificacoes-e-bots, alertas-operacionais | colmex-comercio |
| Torre e visão confiável de métricas e custos | metricas-e-custos | identidade-ui, espaco-e-densidade, mobile-e-responsividade, estados-assincronos | colmex-casas |
| Telegram, volume de mensagens e suspeita de banimento | notificacoes-e-bots | estados-assincronos, metricas-e-custos, alertas-operacionais | Contexto operacional encontrado |
| Laboratório, execuções e organização visual | estados-assincronos | versoes-e-rastreabilidade, contratos-e-dados, identidade-ui, mobile-e-responsividade, simulacao-e-producao | colmex-casas |
| Mercado, lojas, fornecedores e países | elegibilidade-comercial | revisar-arquitetura, contratos-e-dados, setup-integracoes, migracoes-e-compatibilidade, simulacao-e-producao | colmex-comercio |
| Indústria, YouDraw e setup de fornecedores | setup-integracoes | estados-assincronos, elegibilidade-comercial, assets-e-imagens | colmex-comercio |
| Amostras, variantes e prévias de frente e costas | assets-e-imagens | interacoes-diretas, estados-assincronos, setup-integracoes, elegibilidade-comercial, simulacao-e-producao | colmex-comercio |
| Colmeia, abelhas, flores e capacidade de IA real | orquestracao-ias | identidade-ui, interacoes-diretas, performance, estados-assincronos, metricas-e-custos | colmex-colmeia |
| Processos que não usam IA ou usam condicionalmente | orquestracao-ias | contratos-e-dados, estados-assincronos | colmex-colmeia; stack pertinente |
| Menus, botões enormes, alinhamento e espaço desperdiçado | espaco-e-densidade | identidade-ui, mobile-e-responsividade, interacoes-diretas, acessibilidade | Identidade do projeto |
| Fluxos internos confusos, retorno e perda de contexto | ux-e-navegacao | versoes-e-rastreabilidade, mobile-e-responsividade, estados-assincronos | Área em análise |
| Celular, notebook e ultrawide | mobile-e-responsividade | espaco-e-densidade, mobile-e-responsividade, acessibilidade | Produto correspondente |
| UI com menos texto e interação visual direta | interacoes-diretas | identidade-ui, acessibilidade, estados-assincronos | Produto correspondente |
| Frame rate, freezes e piora durante deploy | performance | estados-assincronos, investigar-bugs, build-ci-dependencias | Stack confirmada no projeto |
| Forró: Home e Estudos | ux-e-navegacao | identidade-ui, espaco-e-densidade, mobile-e-responsividade, mobile-e-responsividade, acessibilidade | forro-mobile |
| Forró: Programação, Eventos, Turmas e Escolas | ux-e-navegacao | identidade-ui, mobile-e-responsividade, mobile-e-responsividade, design-system, validar-entrega | forro-mobile |
| Design system, CLAUDE.md, AGENTS.md e DESIGN.md | design-system | identidade-ui, espaco-e-densidade, acessibilidade | Convenções reais do repositório |
| Limpeza de testes redundantes | testes-redundantes | estrategia-de-testes, build-ci-dependencias | Suíte e riscos do projeto |
| Lacunas de qualidade e testes úteis | estrategia-de-testes | testes-redundantes, code-review, validar-entrega | Suíte e riscos do projeto |
| Code review e diagnóstico de bugs | code-review ou investigar-bugs | contratos-e-dados, seguranca-e-permissoes, migracoes-e-compatibilidade | Diff ou reprodução concreta |
| Transformar o material em capacidades reutilizáveis | [INCORPORACAO.md](../INCORPORACAO.md) | Catálogo, manifesto, templates e avaliação | Repositório desta biblioteca |

## Ampliações incluídas

contratos-e-dados, seguranca-e-permissoes, migracoes-e-compatibilidade, build-ci-dependencias e validar-entrega também servem a contratos de dados, segurança, migrations, dependências, CI e validação integrada que não estavam sempre separados em pedidos anteriores. Foram incluídos para cobrir as consequências comuns das refatorações, sem obrigar sua execução em todas as entregas.

Escolher um principal não significa abrir todos os complementos. Eles indicam onde continuar se a investigação demonstrar outra necessidade.
