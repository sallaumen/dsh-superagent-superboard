# Roteiros de uso

Escolha uma entrada pelo problema observado. As setas abaixo indicam uma possível sequência, não uma obrigação de executar todas as skills.

## Produto incompleto e difícil de usar

1. **coordenar-entregas** descobre áreas, prioridades e o destino das ideias inacabadas.
2. **consolidar-codigo** conclui, simplifica ou retira o trecho escolhido.
3. **ux-e-navegacao** revisa a jornada que precisa funcionar inteira.
4. **validar-entrega** verifica a entrega integrada.

Use revisar-arquitetura se a inconsistência decorrer de responsabilidades mal definidas. Um novo plano não precisa preservar todas as ideias antigas nem apagar seus dados.

## Arquitetura e organização do código

1. **revisar-arquitetura** entende limites, dependências e decisões do domínio.
2. **stratified-design** examina níveis de abstração em um fluxo representativo.
3. **organizar-modulos** reorganiza nomes, módulos e APIs com o desenho já compreendido.
4. **contratos-e-dados** ou **migracoes-e-compatibilidade** trata contratos e compatibilidade quando afetados.
5. **code-review** revisa o diff; **validar-entrega** valida o resultado combinado.

Não comece movendo pastas apenas para produzir uma árvore visualmente simétrica. Nem toda melhoria arquitetural exige uma nova camada física.

## Salto de qualidade visual

1. **ux-e-navegacao** se a jornada estiver confusa; caso contrário, comece em **identidade-ui**.
2. **identidade-ui** define uma composição e identidade coerentes com a tarefa.
3. **espaco-e-densidade** corrige proporções, alinhamento e uso do espaço.
4. **mobile-e-responsividade** verifica adaptação funcional a diferentes telas.
5. **interacoes-diretas** melhora os controles que realmente se beneficiam de interação visual.
6. **acessibilidade** verifica as barreiras relevantes; **validar-entrega** confere o fluxo inteiro.

Esses passos podem ser lotes de uma mesma frente. Não abra seis agentes para editar a mesma UI. design-system registra padrões que já demonstraram valor para futuras entregas.

## Aplicativo mobile ou site mobile first

Use **ux-e-navegacao**, **mobile-e-responsividade** e **mobile-e-responsividade** com o contexto pertinente. Valide o retorno com modal aberta, acesso direto por URL, fechamento pelo botão, recarga e navegação normal. Uma tela em 390 pixels de largura não demonstra por si só o comportamento do histórico no aparelho.

No projeto de forró, carregue `forro-mobile` e trate Programação, Eventos, Turmas e Escolas como uma entrega de integração visual e de navegação, preservando a semântica de cada entidade.

## Fornecedores, amostras e mercado

Comece por **setup-integracoes** quando a dificuldade for configurar e saber o que falta. Use **elegibilidade-comercial** para elegibilidade real por variante, fornecedor e destino. Acrescente **assets-e-imagens** para imagens e prévias e **estados-assincronos** para atualizações assíncronas. **simulacao-e-producao** verifica a separação entre jogo, simulação e efeitos reais.

A arquitetura precisa responder o que pode ser oferecido antes de a UI celebrar disponibilidade. Um preview bonito não comprova capacidade de fabricação.

## Colmeia, agentes e operação visual

Use **orquestracao-ias** para o contrato de capacidade e execução, **estados-assincronos** para o estado em tempo real e **identidade-ui/interacoes-diretas** para a cena visual. Carregue `colmex-colmeia`. Se houver freezes, use **performance** com medidas antes e depois, preservando a correspondência entre animação e execução.

## Telegram, notificações e alertas repetidos

**notificacoes-e-bots** investiga transporte, retries, consumo e volume. **alertas-operacionais** trata deduplicação e ciclo do problema apresentado à pessoa. **estados-assincronos** pode ser necessário para atualização da interface; **metricas-e-custos**, para contagens cuja origem esteja confusa. Suspeita de banimento não é diagnóstico.

## Testes e qualidade da mudança

Use **testes-redundantes** quando o problema for redundância de cobertura. Use **estrategia-de-testes** quando a confiança nos comportamentos importantes for insuficiente. Use **code-review** sobre um diff concreto. Use **investigar-bugs** para um bug reproduzível, mesmo quando ainda não houver diff. testes-redundantes não autoriza remover testes apenas porque têm arranjo parecido.

## Preparação para integração

**coordenar-entregas** coordena dependências e entregas; **seguranca-e-permissoes/migracoes-e-compatibilidade/build-ci-dependencias** entram somente quando segurança, compatibilidade ou build forem parte real do risco. **validar-entrega** reúne a evidência final. A etapa de publicação segue a autorização da sessão e as regras do projeto.

## Incorporação de novas fontes a esta biblioteca

Use [INCORPORACAO.md](../INCORPORACAO.md) para registrar origem, destino e decisão de cada conteúdo novo. Essa tarefa analisa e organiza o material; não deve disparar as skills contra o repositório que abriga a biblioteca. A IA decide quais workflows merecem skills próprias, quais são referências e quais devem ser unificados, mantendo a rastreabilidade da decisão.
