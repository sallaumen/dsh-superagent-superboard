---
name: "mobile-e-responsividade"
title: "Experiência mobile, histórico de navegação e adaptação entre telas"
category: "interface"
default_mode: "analisar-e-corrigir"
origem: ["P12", "P13"]
related: ["ux-e-navegacao", "identidade-ui", "espaco-e-densidade", "interacoes-diretas", "acessibilidade", "validar-entrega"]
description: "Use quando o uso no celular falha (voltar fecha a página, modais deixam entradas fantasmas, a navegação perde estado) ou quando a composição desperdiça monitores amplos ou fica comprimida no celular. Valida a adaptação funcional em celular, notebook e ultrawide com evidência visual."
---

# Experiência mobile, histórico de navegação e adaptação entre telas

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

**Mobile e histórico de navegação.** Quando a aplicação depende de uso no celular, especialmente se voltar fecha a página inteira, modais deixam entradas fantasmas ou a navegação perde o estado. Use o workflow de adaptação entre telas desta mesma skill para avaliar a composição em vários monitores.

**Adaptação entre tamanhos de tela.** Quando uma área funciona em um tamanho de tela, mas desperdiça monitores amplos, exige rolagem excessiva ou fica comprimida no celular. O foco é a adaptação funcional da composição e de seus estados.

## Entradas úteis

**Mobile e histórico.**
- Fluxos mobile prioritários e plataformas realmente suportadas.
- Tipo de aplicação e recursos de roteamento existentes.
- Dispositivos ou navegadores disponíveis para validação.

**Adaptação entre telas.**
- Fluxos já implementados e tamanhos de tela prioritários.
- Capturas antes da revisão e acesso à aplicação, se disponíveis.
- Restrições de dispositivo, orientação, zoom ou navegação.

## Workflow A: Mobile e histórico de navegação

### Instrução

Revise o escopo informado com prioridade para uso real no celular. Quero controles legíveis, interação confortável por toque e navegação previsível. Dê atenção especial ao histórico: voltar deve desfazer a etapa de navegação apropriada, preservando o contexto, e fechar uma sobreposição navegável antes de abandonar a página que a abriu.

### Entenda a implementação e os comportamentos esperados

Investigue o roteador, os links, os diálogos, as folhas deslizantes e as transições existentes. Identifique o que já utiliza histórico do navegador e o que existe apenas no estado local. Verifique as plataformas suportadas sem presumir que todos os sistemas oferecem o mesmo gesto, na mesma lateral, ou o mesmo comportamento.

Defina uma pequena matriz de casos: abrir a página por navegação interna; entrar por link direto; abrir um detalhe sobre a página; fechar pelo controle visual; voltar; avançar; recarregar; alternar rapidamente entre itens. Inclua sobreposições encadeadas somente onde fizerem parte do produto. Tooltips e mensagens transitórias não precisam virar etapas do histórico.

### Faça o histórico representar a navegação

Escolha uma estratégia compatível com a arquitetura atual para associar rotas e estados de navegação relevantes. Ao voltar de um diálogo navegável, restaure a tela subjacente e o contexto adequado. Fechar pelo botão da interface deve produzir comportamento consistente, sem deixar entradas vazias que obriguem novos toques para sair.

Considere explicitamente um detalhe aberto por link direto, sem página anterior interna. Nesse caso, ofereça um retorno coerente sem assumir que existe uma entrada segura para remover do histórico. Preserve links compartilháveis quando forem úteis e valide o comportamento de recarregar e avançar depois de fechar um detalhe.

Não bloqueie permanentemente o botão de voltar nem crie ciclos que impeçam sair da aplicação. Navegar pelo histórico não pode reenviar formulários, disparar compras, duplicar alterações ou repetir outras operações de negócio. Separe restauração de estado de comandos com efeitos externos.

Quando houver alterações não salvas, avalie preservação de rascunho ou confirmação proporcional à perda real. Não interrompa toda navegação com diálogos genéricos. Respeite decisões já confirmadas e mantenha uma saída compreensível.

### Refine a interação no telefone

Organize o conteúdo por tarefa e prioridade, com ações identificáveis e áreas de toque confortáveis. Use rótulos suficientes para compreender consequências. Não dependa de hover, gestos secretos ou ícones ambíguos para funções essenciais.

Verifique teclado virtual, campos em foco, mensagens de erro, rolagem, mudanças de orientação e regiões ocupadas pelo sistema ou navegador. Controles fixos não podem esconder o campo ativo ou o resultado da ação. Evite bloquear toda a rolagem quando apenas uma sobreposição precisa conter o foco e o deslocamento.

Preserve foco e contexto ao abrir e fechar elementos. Quando uma resposta assíncrona chegar depois de uma troca de tela, ela não deve reabrir uma sobreposição dispensada ou substituir a seleção atual. Trate o retorno de uma aba em segundo plano e a reconexão sem recriar operações já enviadas.

### Corrija e valide os casos relevantes

No modo de correção, implemente uma solução reutilizável onde os mesmos padrões se repetem. Evite handlers de histórico independentes em cada componente e interceptações globais que alterem páginas fora do escopo. Verifique consumidores do componente compartilhado que for modificado.

Execute a matriz de navegação e confira toques rápidos, fechamento enquanto carrega, erros e ausência de histórico interno. Use emulação para investigar layout e estados, mas registre separadamente os comportamentos confirmados em navegadores ou dispositivos reais. Se não tiver acesso ao dispositivo necessário, descreva o teste pendente sem afirmar que o gesto nativo foi validado.

Entregue os comportamentos definidos, os problemas corrigidos, o mecanismo adotado e as evidências disponíveis. Conclua quando os caminhos prioritários tiverem ida e retorno consistentes, conteúdo acessível com o teclado aberto e ações sem duplicação. Relate diferenças remanescentes entre plataformas de forma concreta.

## Workflow B: Adaptação da composição em celular, notebook e ultrawide

### Instrução

Revise os fluxos do escopo informado em celular, notebook e monitor ultrawide. Quero que cada formato aproveite seu espaço com uma composição útil, mantendo identidade, legibilidade e acesso às mesmas capacidades. Dê atenção especial aos monitores amplos, nos quais uma interface estreita e vertical pode esconder relações que poderiam estar visíveis lado a lado.

### Defina uma matriz representativa

Use os dispositivos prioritários do projeto. Quando não houver definição, comece com viewports de 390 × 844, 1366 × 768 e 3440 × 1440 pixels CSS, em zoom de 100%, e registre esses parâmetros. Esses tamanhos são pontos de inspeção, não limites rígidos nem prova de cobertura completa. Confira também transições de largura e situações relevantes de zoom.

Selecione páginas principais e internas, formulários, diálogos, listas, detalhes e visualizações. Inclua conteúdo vazio, abundante, parcial e carregando, além de títulos longos e erros. Verifique a área útil do conteúdo depois de cabeçalhos e navegação; largura de monitor e espaço realmente disponível à tarefa podem diferir.

### Adapte a composição à tarefa

No celular, priorize a ação atual, a leitura e o toque. Reorganize informações por ordem de decisão e revele detalhes sem esconder sua existência. No notebook, evite que cabeçalhos, navegação e painéis de configuração consumam a maior parte da altura. No ultrawide, aproveite a largura para aproximar seleção, comparação, prévia e resultado quando isso ajudar a trabalhar.

Considere colunas, painéis de detalhe, agrupamentos horizontais e áreas de inspeção contextual. Não multiplique colunas automaticamente nem espalhe informações relacionadas pelas extremidades. Limites de largura continuam úteis para texto corrido; uma leitura confortável pode coexistir com uma área operacional mais ampla.

Não resolva a adaptação apenas aumentando a largura máxima do contêiner ou reduzindo o tamanho da fonte. Verifique proporções de controles, tamanhos de imagem, alinhamento, distribuição de ações e relação entre conteúdo principal e apoio. Use padrões existentes que já funcionam bem, entendendo por que funcionam e se servem a esta tarefa.

### Reduza a rolagem que atrapalha

Procure manter informações essenciais e ações relacionadas próximas. Remova vazios desnecessários, títulos repetidos e blocos enormes com pouco conteúdo. Evite deixar o controle de execução ou a confirmação de uma seleção muito distante de seu resultado.

O objetivo é reduzir deslocamentos e procura, não proibir toda rolagem. Não esconda conteúdo com alturas fixas, fontes minúsculas, abas sem indicação ou barras internas sobrepostas. Conteúdo extenso e usuários com zoom precisam continuar atendidos. Quando uma região rolável for necessária, deixe seus limites e seu comportamento compreensíveis.

Confira diálogos e painéis abertos, não apenas a página inicial. Verifique teclado virtual, foco visível, conteúdo sob barras fixas e menus próximos às bordas. Alternar tamanho ou orientação não deve perder alterações, duplicar elementos interativos ou manter um painel inacessível fora da tela.

### Implemente e verifique a adaptação

No modo de correção, ajuste os componentes e regras de layout responsáveis pelos problemas observados. Escolha pontos de mudança pelo conteúdo e pelo comportamento, evitando coleções de exceções por modelo de dispositivo. Considere efeitos em consumidores compartilhados e preserve o trabalho de outras frentes.

Percorra a mesma tarefa nos três formatos e compare clareza, acesso às ações e continuidade. Confira overflow horizontal acidental e o comportamento entre os pontos de inspeção. Para tabelas ou gráficos que precisam de mais espaço, escolha uma alternativa funcional e preserve acesso à informação completa.

Entregue uma matriz com tamanho, fluxo, problema, correção e evidência. Registre capturas comparáveis antes e depois e diferencie emulação de validação em dispositivo real. Conclua quando as tarefas prioritárias estiverem utilizáveis nos três formatos e as exceções forem justificadas. Não declare suporte universal a dispositivos a partir de três screenshots.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
