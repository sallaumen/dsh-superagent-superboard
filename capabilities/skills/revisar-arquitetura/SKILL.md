---
name: "revisar-arquitetura"
title: "Revisão arquitetural orientada ao domínio"
category: "arquitetura"
default_mode: "analisar-e-corrigir"
origem: ["P03"]
related: ["stratified-design", "organizar-modulos", "contratos-e-dados", "migracoes-e-compatibilidade"]
description: "Use quando mudanças atravessam muitos módulos, regras se repetem, dependências formam ciclos ou os limites de responsabilidade ficaram difíceis de explicar. Para apenas renomear ou mover módulos, prefira organizar-modulos; para níveis de abstração dentro de um recorte, stratified-design."
---

# Revisão arquitetural orientada ao domínio

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando mudanças atravessam muitos módulos, regras se repetem, dependências formam ciclos ou os limites de responsabilidade ficaram difíceis de explicar. Para apenas renomear ou mover módulos, prefira organizar-modulos; para examinar níveis de abstração dentro de um recorte, stratified-design.

## Entradas úteis

- Área, fluxo ou dificuldade que motivou a revisão. Na ausência disso, descubra os fluxos principais e selecione um recorte justificável.
- Restrições de compatibilidade, escala e entregas em andamento, quando conhecidas.
- Modo de trabalho: analisar e corrigir por padrão; somente analisar se solicitado.

## Instrução

Revise criticamente a arquitetura do escopo informado e melhore sua capacidade de sustentar as funcionalidades reais do projeto. Investigue o sistema antes de propor uma estrutura. Trabalhe em mudanças delimitadas e verificáveis; não transforme esta revisão em uma reescrita integral sem necessidade demonstrada.

### Entenda o sistema que existe

Leia as instruções do repositório, a documentação relevante, os pontos de entrada e os caminhos efetivamente usados. Identifique objetivos do produto, atores, entidades, regras de negócio, integrações, persistência e execução assíncrona. Distinga arquitetura documentada, arquitetura implementada e comportamento observado. Um plano antigo ou um nome de pasta não comprova o funcionamento atual.

Escolha fluxos representativos e acompanhe uma ação desde a entrada até seus efeitos e a resposta ao usuário. Registre quem decide, quem executa, quem persiste e quem apresenta o resultado. Investigue também falha, repetição, concorrência e recuperação quando essas condições alterarem a responsabilidade dos componentes.

### Encontre problemas com consequência concreta

Mapeie limites de domínio, proprietários dos dados, contratos públicos e direção das dependências. Procure regras duplicadas, acesso indevido ao estado de outro contexto, dependências circulares, efeitos escondidos, serviços que concentram responsabilidades incompatíveis e abstrações cujo custo excede o benefício.

Para cada problema relevante, mostre o caminho de código ou fluxo que o comprova e explique sua consequência: mudança arriscada, decisão inconsistente, manutenção difícil, perda de isolamento, teste frágil ou falha operacional. Separe defeitos demonstrados de hipóteses e preferências pessoais. Quantidade de linhas, arquivos ou subpastas pode orientar investigação, mas não determina qualidade arquitetural.

Não suponha que cada tela, área do produto ou grupo de pastas deva corresponder a um contexto independente. Examine responsabilidades e motivos de mudança. Considere igualmente a possibilidade de juntar componentes fragmentados ou remover uma camada que apenas repassa chamadas.

### Escolha uma direção proporcional

Compare manter a estrutura com ajustes locais, redefinir contratos e reorganizar responsabilidades. Explique o ganho esperado, os custos de migração, a compatibilidade necessária e o que continuará deliberadamente simples. Use os padrões já úteis no projeto; adote novos padrões somente quando resolverem um problema identificado.

Produza um diagrama compacto das dependências relevantes, acompanhado dos fluxos que justificam os limites. Diferencie o estado atual, a proposta e o que vier a ser implementado. Evite diagramas enormes de todos os arquivos que não ajudam a tomar decisões.

Escolha autonomamente as decisões técnicas reversíveis. Se uma escolha mudar o significado do produto, apresente a evidência, uma recomendação e duas ou três opções claras. Enquanto a decisão estiver pendente, continue as partes independentes do trabalho.

### Refatore em etapas que preservem o funcionamento

Estabeleça a condição inicial do recorte. Em seguida, organize uma sequência em que cada etapa tenha objetivo, contratos afetados, estratégia de compatibilidade e critério de conclusão. Priorize corrigir responsabilidades e dependências antes de renomear a árvore inteira.

No modo de correção, implemente o recorte escolhido, atualizando consumidores, documentação pertinente e verificações que protegem o comportamento. Considere usos dinâmicos, extensões, configurações e referências persistidas, além de chamadas encontradas por busca textual. Evite duas implementações permanentes da mesma regra durante a transição. Se necessário, introduza uma ponte de compatibilidade com condição explícita de remoção.

Não altere contratos externos, dados históricos ou infraestrutura de produção por suposição. Respeite as autorizações já existentes e delimite qualquer etapa que dependa de acesso ou decisão ainda indisponível.

### Demonstre o resultado e encerre o recorte

Valide os fluxos afetados e as fronteiras que mudaram, incluindo os casos de falha relevantes. Prefira testes de comportamento e contratos a verificações que congelam a nova organização interna. Identifique falhas anteriores à mudança para não atribuí-las à refatoração.

Entregue o diagnóstico priorizado, as decisões e alternativas consideradas, os diagramas úteis, as alterações realizadas e a evidência de validação. Inclua um exemplo concreto de antes e depois que explique por que ficou mais fácil compreender ou modificar o sistema. Separe o que está implementado do que permanece proposto.

Considere esta rodada concluída quando o recorte cumprir seus critérios e as dependências afetadas estiverem coerentes. Registre melhorias futuras com motivo e prioridade; não amplie indefinidamente a refatoração apenas porque novas oportunidades apareceram.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
- Modelo de registro: [templates/registro-de-decisao.md](../../templates/registro-de-decisao.md)
