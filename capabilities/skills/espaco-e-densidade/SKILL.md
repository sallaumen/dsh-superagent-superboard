---
name: "espaco-e-densidade"
title: "Organizar espaços, alinhamentos e densidade de informação"
category: "interface"
default_mode: "analisar-e-corrigir"
origem: ["P10"]
related: ["identidade-ui", "ux-e-navegacao", "mobile-e-responsividade", "acessibilidade", "design-system"]
description: "Use quando existem desalinhamentos, áreas vazias desproporcionais, botões esticados ou informação importante enterrada em páginas longas. Concentra-se na composição e no aproveitamento do espaço, mantendo os dados e as regras atuais."
---

# Organizar espaços, alinhamentos e densidade de informação

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando existem desalinhamentos, áreas vazias desproporcionais, botões esticados ou informação importante enterrada em páginas longas. A intervenção se concentra na composição e no aproveitamento do espaço, mantendo os dados e as regras atuais.

## Entradas úteis

- Páginas ou fluxo a revisar, incluindo páginas internas.
- Telas mais utilizadas e exemplos de conteúdo realista.
- Restrição de identidade visual ou componentes compartilhados, se existir.

## Instrução

Revise a organização espacial de todas as páginas internas do escopo informado. Quero alinhamento, proporção, boa leitura e acesso rápido às informações relevantes. Você tem autonomia para reconstruir composições ruins e simplificar estruturas de interface. Preserve o significado dos dados e das ações; não transforme esta tarefa em uma mudança de produto sem necessidade.

### Faça uma leitura estrutural da área

Mapeie páginas, estados e componentes repetidos. Identifique onde começam e terminam o conteúdo principal, a navegação, os controles de contexto e os detalhes. Examine a aplicação com conteúdo realista: listas grandes e pequenas, nomes longos, ausência de imagens, erros e carregamento.

Localize desalinhamentos, margens inconsistentes, níveis demais de contêineres, cabeçalhos excessivos, cards de tamanho desproporcional e controles que ocupam largura sem ganhar utilidade. Verifique se o problema vem do componente, de uma regra global ou da composição da página. Evite consertos locais que criem novas divergências entre telas equivalentes.

Observe o custo do espaço: que informação fica fora da primeira área visível, quais elementos obrigam a rolar repetidamente e quais regiões parecem vazias enquanto outras estão congestionadas? Registre exemplos concretos antes de escolher uma solução. Uma screenshot isolada não demonstra como o layout se comporta com outros conteúdos.

### Reorganize segundo importância e relacionamento

Defina uma grade e uma escala de espaçamento compatíveis com o sistema existente. Alinhe bordas, títulos, valores, ações e áreas de interação. Agrupe o que participa da mesma decisão e separe conjuntos com funções diferentes. Use proximidade e hierarquia antes de acrescentar mais caixas, divisórias ou títulos.

Dimensione botões pela função, pelo rótulo e pelo contexto. Não estique uma ação pequena apenas para preencher um card. Também não a reduza a ponto de dificultar toque, foco ou leitura. Distribua os elementos com proporções úteis; igualdade visual entre colunas não é uma obrigação quando seus conteúdos têm necessidades diferentes.

Considere composição horizontal em telas amplas: resumo e detalhe, seleção e prévia, lista e inspeção ou controles próximos do resultado. No celular, reorganize por prioridade e sequência da tarefa. Evite transportar uma coluna excessivamente comprida para o centro de um monitor grande ou comprimir uma composição de desktop inteira na largura do telefone.

Reduza redundâncias, espaços artificiais e explicações repetidas. Preserve informações que sustentam decisões. Detalhes ocasionais podem aparecer em expansão, painel contextual ou diálogo, desde que sua existência e seu acesso sejam claros. Não esconda um problema de layout transferindo todo o conteúdo para modais.

### Trate rolagem e tamanho com julgamento

Busque reduzir a rolagem necessária para a tarefa principal, sem prometer uma interface inteira sem rolagem. Conteúdo extenso, acessibilidade, tradução e zoom podem exigir espaço. Prefira uma página bem organizada a fontes pequenas, alturas fixas que cortam conteúdo ou múltiplas barras internas difíceis de controlar.

Use regiões fixas ou aderentes apenas quando ajudarem a manter contexto e ações disponíveis. Verifique se cobrem mensagens, campos, foco ou conteúdo quando o teclado aparece. Em tabelas e listas extensas, escolha paginação, expansão ou virtualização conforme o problema demonstrado, preservando busca, leitura e navegação.

### Implemente, confira e entregue

No modo de correção, ajuste o menor conjunto coerente de componentes e páginas. Se alterar um componente compartilhado, identifique consumidores e confira os que podem sofrer regressão. Evite seletores globais indiscriminados e valores compensatórios espalhados que escondam a causa do desalinhamento.

Valide na aplicação os tamanhos relevantes de tela, nomes longos, ausência de dados, zoom e mudanças de estado. Compare se a tarefa principal exige menos busca visual e menos deslocamento entre informações relacionadas. Não declare ganho de produtividade quantitativo sem medição.

Entregue comparações visuais, componentes afetados, decisões de composição e situações verificadas. A revisão termina quando o escopo possui alinhamentos consistentes, proporções funcionais e controles acessíveis, sem cortes ou regressões conhecidos. Registre melhorias de produto ou arquitetura descobertas como próximos trabalhos delimitados.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
