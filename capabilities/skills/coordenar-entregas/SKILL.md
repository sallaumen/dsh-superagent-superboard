---
name: "coordenar-entregas"
title: "Coordenar entregas: consolidação do produto e integração entre frentes"
category: "coordenacao"
default_mode: "coordenar"
origem: ["P01", "P02"]
related: ["consolidar-codigo", "code-review", "validar-entrega"]
description: "Use para consolidar um produto por áreas (descobrir o que concluir, simplificar ou retirar e conduzir ciclos de melhoria) e para dividir uma mudança já definida em entregas revisáveis, coordenando no máximo duas frentes executoras e integrando sequencialmente. Para um bug pontual, use investigar-bugs."
---

# Coordenar entregas: consolidação do produto e integração entre frentes

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`coordenar`). Uma instrução explícita da sessão prevalece. Coordenar não concede permissão de merge, deploy ou publicação.

## Quando usar

**Consolidação do produto por áreas.** Quando o projeto acumula áreas incompletas, planos antigos e interfaces desconectadas, e precisa de uma sequência de entregas que torne o produto coerente. Para um bug pontual, use investigar-bugs.

**Planejamento de entregas, PRs e integração.** Quando uma mudança já está definida, mas precisa ser dividida, implementada e integrada com segurança entre frentes. A descoberta das prioridades de produto pertence ao workflow de consolidação de `coordenar-entregas`.

## Entradas úteis

**Consolidação.**
- Objetivo do produto e área inicial, se houver. Caso contrário, descubra as áreas no projeto.
- Restrições de entrega e decisões já tomadas. Limite padrão: duas frentes executoras.

**Entregas.**
- Resultado esperado, base de integração e trabalhos em andamento.
- Autorizações de branch, PR, merge e publicação já concedidas na sessão.

## Workflow A: Consolidação do produto por áreas

### Instrução

Assuma a coordenação de uma consolidação do produto. Descubra suas áreas reais e conduza entregas que tornem os fluxos úteis, coerentes e concluídos. Você pode questionar soluções existentes, simplificar funcionalidades e propor retirar ideias que perderam sentido. Uma implementação antiga ou um TODO não constitui, por si só, uma obrigação de terminá-los.

### Descubra o produto antes de distribuir trabalho

Leia as instruções do projeto, rotas, navegação, contextos, modelos, serviços, jobs e documentação de intenção. Percorra os fluxos principais em execução, se o ambiente permitir. Identifique quem usa cada área, que problema ela resolve, quais dados consome e produz, onde começa e como o usuário reconhece que terminou uma tarefa. Não se limite à página inicial de cada área.

Construa um inventário enxuto: área, finalidade, fluxo principal, dependências, estado observado e evidências. Diferencie funcionalidades concluídas, parcialmente implementadas, desabilitadas por configuração, deliberadamente limitadas, abandonadas e impossíveis de avaliar com o acesso disponível. Não classifique uma integração como quebrada apenas porque falta uma credencial no ambiente local.

Compare o que existe com a intenção atual do produto. Procure duplicação de responsabilidades, telas que oferecem ações sem efeito, atalhos que escondem etapas necessárias, dados produzidos sem consumidores e estados que nunca chegam a uma conclusão visível. Inclua os custos de manutenção e de compreensão do usuário na análise.

### Escolha o destino de cada problema

Para cada conjunto coerente de achados, recomende concluir, simplificar, reorganizar, unificar, retirar ou adiar. Justifique pela utilidade e pelas dependências, sem premiar a quantidade de código já escrita. Uma simplificação pode ser a melhor conclusão.

Resolva autonomamente detalhes técnicos reversíveis. Quando a escolha mudar a proposta de uma área, abandonar uma capacidade desejada ou alterar um compromisso com usuários, apresente uma pergunta curta com duas ou três opções e sua recomendação. Enquanto aguarda, avance nas partes independentes. Retirar uma função da navegação não autoriza apagar dados históricos ou quebrar links públicos sem tratamento.

### Conduza um ciclo de entregas

Priorize bloqueios de uso e inconsistências que contaminam várias áreas. Defina a primeira entrega por um resultado observável, como configurar uma integração e concluir uma operação, em vez de uma lista indefinida de melhorias. Mantenha um backlog curto para o restante; não inicie todas as áreas de uma vez.

Use até duas frentes executoras simultâneas quando houver isolamento real. Cada frente recebe escopo, contratos compartilhados, arquivos sob responsabilidade, critério de conclusão e modo de atuação. Uma pessoa ou agente deve responder por mudanças transversais. Evite duas frentes redesenhando o mesmo componente ou alterando a mesma regra de negócio em paralelo.

Após o despacho, mantenha um listener ou mecanismo de espera para receber bloqueios, decisões e conclusões. Não envie mensagens periódicas a agentes ocupados. Intervenha quando precisarem de resposta ou quando surgir um conflito concreto. Se não houver suporte a agentes, execute as mesmas etapas sequencialmente.

Registre área ativa, decisão, branch ou entrega local, verificações e próximo passo para permitir retomada. Prepare PRs e integre conforme as autorizações vigentes. Uma frente concluída isoladamente ainda precisa ser validada com o estado integrado.

### Valide uma área inteira antes de expandir

Exercite o fluxo de entrada, operação principal, erro recuperável e retorno à navegação. Verifique se as dependências continuam coerentes e se o usuário reconhece o que falta fazer. Não transforme cada ajuste de UI em um novo projeto arquitetural; corrija a causa necessária e registre problemas independentes para outra entrega.

Encerre cada ciclo quando o resultado combinado estiver implementado e validado, ou quando um impedimento essencial estiver demonstrado. Entregue um mapa das áreas, decisões tomadas, alterações concluídas, evidências, decisões pendentes e a próxima área recomendada. Mostre claramente o que foi retirado, preservado ou adiado e por quê. Não confunda um plano abrangente com uma melhoria efetivamente entregue.

## Workflow B: Planejamento de entregas, PRs e integração

### Instrução

Organize e conduza a entrega indicada em lotes revisáveis. Seu objetivo é preservar a coerência do produto enquanto reduz conflitos, retrabalho e mudanças difíceis de verificar. Mantenha autonomia sobre escolhas técnicas locais; use as autorizações existentes para ações externas e não presuma que coordenar uma entrega autoriza publicar em produção.

### Estabeleça o ponto de partida

Inspecione o estado do repositório, a base pretendida, alterações locais, branches e instruções de contribuição relevantes. Identifique quem já está modificando componentes ou contratos envolvidos. Não descarte mudanças alheias, não faça reset destrutivo e não trate todos os arquivos modificados como seus.

Registre o baseline necessário para distinguir falhas anteriores de regressões. Entenda o comportamento que deve mudar e o que consumidores atuais esperam. Liste dependências reais entre UI, domínio, persistência, integrações e jobs. Verifique se alguma entrega precisa conviver temporariamente com código de versões diferentes, como em um deploy gradual.

### Divida por resultados verificáveis

Proponha lotes pequenos o suficiente para revisão, mas capazes de demonstrar comportamento útil. Uma divisão artificial por pasta pode deixar várias partes inutilizáveis; prefira fatias funcionais quando reduzirem esse risco. Para cada lote, indique objetivo, arquivos ou contratos afetados, dependências, compatibilidade, validação e como interromper ou reverter se necessário.

Escolha uma sequência explícita. Mudanças de contrato compartilhado precisam de um responsável e de consumidores conhecidos. Se uma alteração preparatória puder ser integrada sem mudar o comportamento, explique essa escolha. Não crie abstrações, flags ou adaptadores temporários sem necessidade demonstrável e sem uma condição de remoção.

Use no máximo duas frentes executoras em paralelo por padrão. Delegue apenas trabalhos que possam avançar sem disputa pelos mesmos arquivos e decisões. Dê a cada frente o contexto mínimo suficiente e um critério de conclusão. Mantenha a coordenação de contratos compartilhados centralizada.

### Integre com disciplina

Trabalhe em branches ou worktrees isolados quando apropriado. Espere eventos de conclusão ou bloqueio; evite interromper agentes para pedir status. Responda a decisões pendentes com uma orientação concreta e registre mudanças de contrato para os consumidores afetados.

Antes de integrar uma frente, leia o diff completo, confirme escopo e verifique que os testes ou evidências correspondem ao comportamento alterado. Resolva conflitos entendendo a intenção dos dois lados. Um merge sem marcadores de conflito não demonstra que o comportamento combinado continua correto.

Siga as regras do repositório para revisão, checks e atualização da base. Integre sequencialmente, conferindo o estado após cada lote. Não contorne proteção de branch, não force publicação e não use uma autorização de teste como permissão de deploy. Quando faltar autorização de merge, deixe a mudança ou PR concretamente pronto e informe o que falta.

### Valide o produto integrado

Execute os gates exigidos e os cenários que atravessam as fronteiras alteradas. Valide compatibilidade de dados, configuração, migrations e consumidores persistidos quando aplicável. Não repita toda a suíte sem motivo a cada microajuste; amplie a verificação para resolver riscos novos ou cumprir gates estabelecidos.

Se uma integração falhar, preserve evidências e contenha a regressão. Prefira uma correção delimitada ou reversão compatível com os dados já produzidos. Reverter código não necessariamente reverte efeitos externos ou mudanças de esquema; trate esses casos explicitamente.

### Entrega

Mantenha um registro curto com lote, responsável, dependências, branch ou PR, checks, estado de integração e bloqueio. Escreva descrições de PR explicando o problema, a mudança e o comportamento resultante, com validações úteis ao revisor.

Conclua quando os lotes autorizados estiverem integrados e verificados, ou quando houver um impedimento concreto com uma entrega revisável. Diferencie trabalho local, PR aberto, aprovação, merge, deploy e validação após deploy. Não declare sucesso usando apenas o relato das frentes. Indique a próxima ação necessária sem iniciar automaticamente uma nova fase de produto.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
- Modelo de registro: [templates/plano-de-entrega.md](../../templates/plano-de-entrega.md)
