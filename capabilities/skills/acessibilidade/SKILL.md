---
name: "acessibilidade"
title: "Revisar acessibilidade e corrigir barreiras de uso"
category: "interface"
default_mode: "analisar-e-corrigir"
origem: ["P15"]
related: ["identidade-ui", "mobile-e-responsividade", "interacoes-diretas", "design-system", "validar-entrega"]
description: "Use quando fluxos possuem controles visuais, mudanças assíncronas, modais, formulários ou navegação que podem excluir usuários, ou após uma mudança importante de UI. O resultado é uma avaliação delimitada, sem alegação automática de conformidade integral."
---

# Revisar acessibilidade e corrigir barreiras de uso

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando fluxos possuem controles visuais, mudanças assíncronas, modais, formulários ou navegação que podem excluir usuários. Também é apropriado após uma mudança importante de UI. O resultado é uma avaliação delimitada, sem alegação automática de conformidade integral.

## Entradas úteis

- Fluxos prioritários, público e tecnologias suportadas.
- Política ou padrão de acessibilidade adotado pelo projeto.
- Ferramentas e dispositivos realmente disponíveis para avaliação.

## Instrução

Avalie e melhore a acessibilidade dos fluxos do escopo informado. Priorize barreiras que impedem entender, navegar, agir ou recuperar erros. Quero preservar a identidade visual e a riqueza das interações, garantindo caminhos equivalentes para quem usa teclado, toque, leitores de tela, zoom ou preferências de redução de movimento.

### Delimite a avaliação e estabeleça evidências

Leia as orientações de acessibilidade do projeto e identifique páginas, componentes e estados relevantes. Se usar um padrão externo, confirme sua versão e os critérios aplicáveis em fonte oficial antes de citar limites ou declarar atendimento. Diferencie uma verificação parcial de uma auditoria formal.

Explore primeiro as tarefas principais. Registre barreiras com localização, passos de reprodução, impacto e evidência. Agrupe falhas de uma mesma causa em componentes compartilhados. Verificações automáticas ajudam a localizar problemas, mas não demonstram sozinhas que a tarefa é compreensível e concluível.

### Examine estrutura, controles e navegação

Confira estrutura de títulos, regiões, ordem de leitura e significado dos elementos. Prefira controles nativos quando forem adequados e verifique os contratos de componentes personalizados. Evite corrigir semântica acrescentando atributos que contradizem o elemento ou anunciam estados que não existem.

Percorra o fluxo por teclado: ordem de foco, indicação visível, abertura, seleção, confirmação e retorno. Diálogos devem manter um comportamento de foco coerente e devolver o usuário a um ponto útil ao fechar. Confirme que é possível sair de componentes e que regiões fixas não escondem o foco.

Inspecione nomes, rótulos, instruções, agrupamentos e mensagens de erro. Ícones e botões precisam de significado compreensível, inclusive fora do contexto visual imediato. Formulários devem relacionar erro ao campo e orientar a correção sem apagar dados válidos. Não dependa apenas de placeholder, posição ou cor.

### Trate conteúdo visual e atualizações

Avalie contraste, legibilidade, zoom, reorganização do conteúdo e áreas de interação conforme os requisitos aplicáveis. Confira estados de foco, selecionado, desabilitado, carregando e erro. Diferencie uma opção indisponível de informação desconhecida e deixe o motivo acessível.

Para imagens, gráficos, mapas, cenas ou visualizações ricas, identifique a informação ou ação essencial e forneça uma representação equivalente apropriada. Uma descrição genérica de que existe uma imagem não substitui dados necessários para decidir. Uma cena interativa pode manter sua linguagem visual e oferecer seleção, detalhes e estado em uma estrutura navegável.

Revise anúncios de conteúdo assíncrono para que resultados importantes sejam percebidos sem uma sequência incessante de mensagens. Atualizações frequentes não devem roubar foco, reconstruir a região ativa ou reiniciar a leitura. Separe progresso relevante de ruído operacional.

Respeite preferências de movimento quando houver animações e preserve o significado da transição com alternativas discretas. Pausar uma animação decorativa não pode pausar o trabalho real do sistema. Recursos essenciais não devem exigir hover, precisão excessiva de movimento ou execução rápida de uma sequência.

### Corrija com alcance conhecido

No modo de correção, priorize bloqueios de tarefa e causas compartilhadas, mantendo o comportamento de negócio. Verifique componentes de terceiros e documente limitações que não puderem ser resolvidas no escopo. Não substitua uma interação rica por uma experiência incompleta apenas para silenciar uma ferramenta automática.

Valide as correções com os métodos pertinentes: navegação manual, inspeção de semântica, ferramentas disponíveis e tecnologias assistivas quando acessíveis. Registre ambiente, cenários e resultados. Se não houver leitor de tela ou dispositivo real disponível, declare exatamente o que ficou sem verificação e forneça passos objetivos para completar a avaliação.

Entregue uma lista priorizada de barreiras, alterações realizadas, evidências e limitações remanescentes. Diferencie critérios confirmados, verificações parciais e hipóteses. Conclua quando as barreiras delimitadas estiverem corrigidas e verificadas, ou quando impedimentos concretos estiverem documentados. Não declare que toda a aplicação é acessível a partir de uma pontuação automática ou de uma única página.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
- Fontes e conceitos: [referencias/fontes-e-conceitos.md](../../referencias/fontes-e-conceitos.md)
