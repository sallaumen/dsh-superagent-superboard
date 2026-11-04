---
name: "identidade-ui"
title: "Refinar a identidade da UI e remover soluções visuais genéricas"
category: "interface"
default_mode: "analisar-e-corrigir"
origem: ["P09"]
related: ["espaco-e-densidade", "ux-e-navegacao", "interacoes-diretas", "design-system", "assets-e-imagens"]
description: "Use quando a aplicação funciona, mas parece uma coleção de componentes genéricos, sem hierarquia, personalidade ou relação clara com a tarefa. Para uma intervenção concentrada em espaços e proporções, use espaco-e-densidade."
---

# Refinar a identidade da UI e remover soluções visuais genéricas

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando a aplicação funciona, mas parece uma coleção de componentes genéricos, sem hierarquia, personalidade ou relação clara com a tarefa. Use espaco-e-densidade para uma intervenção concentrada em espaços; use esta skill quando a composição e a linguagem visual precisam ser reconsideradas.

## Entradas úteis

- Área ou conjunto de páginas. Na ausência de indicação, delimite pelo fluxo em discussão.
- Imagens atuais, referências desejadas e identidade existente, quando disponíveis.
- Público e tarefa principal; descubra no projeto o que estiver documentado.

## Instrução

Revise criticamente a interface do escopo informado e dê a ela uma direção visual coerente com o produto. Quero uma experiência reconhecível, agradável e útil, com decisões de composição que ajudem a entender e agir. Você pode reorganizar, substituir ou remover elementos que prejudiquem esse resultado, preservando os dados e as capacidades necessárias do fluxo.

### Entenda o produto antes de escolher a aparência

Explore as páginas reais, seus estados e os componentes existentes. Leia as orientações de design do repositório. Identifique quem usa a área, qual decisão precisa tomar, quais informações sustentam essa decisão e qual identidade o produto já construiu. Trate screenshots como evidência de um estado específico; confira a aplicação e o código antes de atribuir causas.

Procure problemas observáveis: todos os elementos parecem ter a mesma importância; ações principais não parecem clicáveis; cards repetem rótulos e descrições sem ajudar; ícones são decorativos; painéis enormes contêm pouca informação; informações relevantes estão escondidas; cores e tipografia mudam sem motivo. Relacione cada problema ao esforço ou à incerteza que ele cria para o usuário.

Não defina qualidade por uma lista arbitrária de estilos proibidos. Cards, gradientes, sombras, tabelas e texto podem ser adequados. O problema é usá-los sem propósito, transformar qualquer conteúdo no mesmo bloco ou acrescentar ornamentação que disputa atenção com o trabalho.

### Escolha e aplique uma direção coerente

Formule uma direção curta: hierarquia, ritmo, linguagem das ações, uso de imagem e relação entre áreas. Aproveite padrões bons já presentes e explique as mudanças que terão efeito perceptível. Se houver referências, extraia princípios úteis em vez de copiar sua aparência sem considerar o conteúdo.

Reavalie o enquadramento da página, agrupamentos, navegação local, informação principal e detalhes sob demanda. Dê destaque proporcional à importância das ações e diferencie ação primária, secundária e destrutiva com consistência. Torne a interação reconhecível também por forma, contraste, posição e feedback, sem depender exclusivamente da cor.

Reduza textos que apenas repetem o óbvio. Mantenha rótulos e explicações necessários para decisões, consequências, erros e acessibilidade. Ícones sem significado claro não substituem linguagem compreensível. Em produtos lúdicos, use a metáfora visual para explicar estados e relações reais; em outros produtos, respeite sua identidade sem importar uma estética de jogo.

Cuide dos estados selecionado, carregando, vazio, indisponível, erro, sucesso e informação desatualizada. Uma tela bonita com dados abundantes precisa continuar compreensível quando há um único item, nomes longos ou nenhuma resposta do serviço. Não invente indicadores, números, conteúdo ou capacidades para preencher a composição.

### Implemente uma mudança que se sustente

No modo de correção, trabalhe por um fluxo representativo e seus componentes, ampliando apenas o necessário para manter consistência. Uma reconstrução substancial é válida quando pequenos ajustes preservariam o problema. Mantenha as regras de negócio e faça adaptações de contrato somente quando essenciais à experiência, explicando seu alcance.

Prefira elementos semânticos e componentes compreensíveis a uma montagem visual frágil. Preserve foco, navegação por teclado, áreas de interação adequadas e leitura em diferentes tamanhos. Use movimento para comunicar transições; evite animações que atrasem ações ou indiquem progresso inexistente. Verifique se a solução degrada a fluidez ou depende de efeitos caros repetidos.

### Valide e conclua

Percorra o fluxo na aplicação rodando e compare antes e depois em condições equivalentes. Avalie reconhecimento da ação principal, leitura das informações essenciais, continuidade entre páginas e recuperação de falhas. Confira ao menos o menor e o maior contexto de tela relevantes; registre o que foi efetivamente observado.

Entregue os problemas encontrados, a direção adotada, as mudanças com maior impacto e evidências visuais dos estados relevantes. Diferencie implementação de validação e aponte limitações concretas. Termine quando o fluxo delimitado tiver linguagem visual consistente, ações legíveis e estados completos, sem ampliar indefinidamente a reforma do produto.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
