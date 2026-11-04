---
name: "design-system"
title: "Evoluir o design system e as instruções para futuras implementações"
category: "interface"
default_mode: "analisar-e-corrigir"
origem: ["P16"]
related: ["organizar-modulos", "identidade-ui", "espaco-e-densidade", "mobile-e-responsividade", "acessibilidade"]
description: "Use quando diferentes frentes repetem erros de interface, criam variações incompatíveis ou dependem de instruções vagas. Consolida componentes, tokens e documentação operacional (DESIGN.md, AGENTS.md) em uma fonte de verdade por norma."
---

# Evoluir o design system e as instruções para futuras implementações

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando diferentes frentes repetem erros de interface, criam variações incompatíveis ou dependem de instruções vagas. O objetivo é alinhar componentes, princípios e documentação operacional para futuras alterações.

## Entradas úteis

- Áreas representativas e referências de identidade visual.
- Arquivos de orientação existentes, como DESIGN.md, AGENTS.md ou equivalentes.
- Convenções de componentes, tokens e exemplos já usados pelo projeto.

## Instrução

Revise os padrões visuais e as instruções de implementação do projeto para ajudar futuras pessoas e inteligências artificiais a criar interfaces melhores e mais consistentes. Quero orientações concretas, apoiadas em componentes reais e decisões de produto. Você pode reorganizar documentação e refinar padrões compartilhados no escopo autorizado, preservando instruções válidas e o trabalho de outras frentes.

### Descubra o sistema que realmente existe

Leia os arquivos de orientação aplicáveis e examine componentes, estilos, tokens e páginas representativas. Compare o que está documentado com o que a aplicação usa. Identifique padrões consistentes, exceções justificadas, divergências acidentais e recomendações que não possuem implementação correspondente.

Observe problemas recorrentes: ações principais pouco reconhecíveis, excesso de texto, tamanhos desproporcionais, cores sem semântica, estados incompletos, pouca adaptação a telas amplas ou interações que dependem exclusivamente de mouse. Descubra se a causa é um componente inadequado, uma regra ausente, uma regra contraditória ou dificuldade de localizar um exemplo bom.

Não transforme preferências de uma página em regras universais. Examine contextos diferentes antes de consolidar um padrão e preserve exceções que atendem necessidades reais. Um nome ou formato de arquivo de instrução não garante que todos os agentes e ferramentas o leiam; confira o mecanismo utilizado pelo projeto.

### Defina padrões que ajudem a decidir

Organize princípios de hierarquia, tipografia, espaço, cor, imagens, ações, navegação e movimento. Relacione cada princípio à tarefa do usuário. Prefira critérios verificáveis a frases como “deixe moderno”, “faça premium” ou “use boas práticas”.

Estabeleça uma hierarquia de ações e seus estados. Botões devem parecer interativos, com destaque proporcional à importância, coerência entre páginas e contraste suficiente. Diferencie ações primárias, secundárias, destrutivas e indisponíveis. Preserve a identidade cromática existente quando fizer sentido, mas não atribua todos os significados à mesma cor ou dependa apenas dela.

Defina padrões para carregamento, vazio, erro, sucesso, conteúdo parcial e informação desatualizada. Inclua orientação para seleção, salvamento, confirmação e retorno. Explique quando usar painel, página, expansão ou diálogo, deixando espaço para julgamento conforme o fluxo.

Trate responsividade como adaptação da tarefa. Inclua exemplos de celular, notebook e monitor amplo, com leitura confortável e melhor aproveitamento horizontal. Evite regras que imponham ausência absoluta de rolagem, fontes pequenas ou um único layout para todo tipo de conteúdo.

### Conecte orientação, componentes e exemplos

Quando um padrão já tiver implementação confiável, indique o componente e um uso real. Se faltar uma capacidade compartilhada necessária, implemente-a no modo de correção e ajuste consumidores representativos. Evite criar abstrações genéricas sem casos de uso ou distribuir regras contraditórias entre CSS, componentes e documentos.

Mantenha as instruções principais curtas e direcionadoras. Coloque detalhes específicos, exemplos e exceções em referências localizáveis, carregadas conforme a tarefa. Não copie a mesma norma em vários arquivos: defina uma fonte de verdade e links claros. Preserve conteúdo não relacionado e resolva contradições explicitamente, sem reescrever todo o manual por conveniência.

Documente decisões importantes com motivação, limites e forma de verificar. Diferencie padrões implementados de propostas ainda não aplicadas. Para alterações de componentes compartilhados, registre alcance e caminho de adoção; não esconda mudanças incompatíveis sob uma atualização de documentação.

### Verifique utilidade e consistência

Escolha páginas representativas e confira se as orientações permitem tomar decisões concretas. Valide componentes alterados, estados, acessibilidade e tamanhos relevantes. Verifique links e exemplos de código. Se uma regra produzir resultado ruim em um caso legítimo, refine seu alcance em vez de forçar a interface a obedecer.

Entregue padrões consolidados, divergências resolvidas, arquivos alterados, exemplos e pendências de adoção. Explique como uma nova frente encontra a orientação e identifica o componente adequado. Conclua quando a documentação estiver coerente com a implementação delimitada e os erros recorrentes tiverem diretrizes práticas, sem transformar o conjunto em um manual excessivo que ninguém consegue aplicar.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
