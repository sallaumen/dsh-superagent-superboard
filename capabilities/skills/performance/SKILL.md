---
name: "performance"
title: "Investigar performance, frame rate e congelamentos"
category: "operacao"
default_mode: "analisar-e-corrigir"
origem: ["P17"]
related: ["estados-assincronos", "investigar-bugs", "build-ci-dependencias", "validar-entrega"]
description: "Use quando a aplicação apresenta travamentos, animações irregulares, atrasos em interações ou piora durante atualização, reconexão ou deploy. Mede o caminho que realmente falha antes de atribuir causa; consistência de estado assíncrono é estados-assincronos."
---

# Investigar performance, frame rate e congelamentos

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando a aplicação apresenta travamentos, animações irregulares, atrasos em interações ou piora durante atualização, reconexão ou deploy. O foco é descobrir a causa e corrigir o caminho medido, sem transformar todo problema em uma revisão visual.

## Entradas úteis

- Fluxo, página ou interação afetada; na ausência de um caso preciso, reproduza o relato no caminho principal.
- Ambiente, dispositivo e momento do problema, quando conhecidos.
- Restrições de execução e acesso a ferramentas de medição; registre as limitações reais.

## Instrução

Investigue e corrija os problemas de fluidez no escopo desta tarefa. Quero entender o que causa as pausas e receber uma melhoria demonstrável na experiência real. Trate suspeitas como hipóteses até encontrar evidências. Se o modo solicitado for apenas análise, entregue o diagnóstico e a proposta sem alterar a implementação.

### 1. Defina uma reprodução comparável

Leia as instruções do projeto e identifique a stack, o modo de execução e os fluxos envolvidos. Reproduza uma interação concreta: abrir a tela, navegar, selecionar um item, acompanhar uma operação ou reconectar. Registre tamanho de tela, dispositivo ou emulação, navegador, volume de dados, estado do cache e condições de rede relevantes. Separe o comportamento em desenvolvimento daquele observado em uma versão representativa de produção.

Não atribua automaticamente um congelamento ao frontend, à animação ou ao deploy. Diferencie ausência de novos dados, bloqueio da interação, demora de uma requisição, atraso do servidor, perda de conexão e irregularidade dos frames. Correlacione o horário do sintoma com o trabalho efetivamente executado, preservando a distinção entre correlação e causa.

### 2. Meça o caminho que realmente falha

Use as ferramentas disponíveis para observar tempo de resposta à interação, distribuição dos tempos de frame, tarefas longas, renderizações, layout, uso de memória e atividade de rede. No servidor, procure consultas, processamento síncrono, filas, saturação ou chamadas externas que expliquem o relato. Escolha poucas medidas que respondam à hipótese, sem criar uma plataforma de observabilidade inteira.

Procure atualizações mais amplas que o necessário, assinaturas duplicadas, listeners acumulados, timers esquecidos, trabalho repetido, listas extensas, cálculos caros no caminho de renderização e ciclos de eventos. Confirme quais deles ocorrem no fluxo observado. Uma média de FPS isolada não deve esconder pausas perceptíveis; considere a duração e a frequência dos piores intervalos e a capacidade do dispositivo.

### 3. Investigue a relação com deploy e reconexão

Quando houver suspeita de deploy, examine a reconexão, a compatibilidade entre versões, a troca de assets e a recuperação do estado. Verifique se inscrições são recriadas duas vezes, eventos antigos são reproduzidos, ações pendentes são reenviadas ou a tela é reconstruída desnecessariamente. Diferencie interrupção esperada do transporte de defeito na recuperação.

Faça experimentos controlados em ambiente autorizado. Não inicie deploys de produção ou testes de carga externos apenas para reproduzir o problema. Se essa evidência depender de acesso indisponível, deixe a hipótese delimitada e instrumente o necessário para a próxima observação, sem afirmar que a causa foi comprovada.

### 4. Corrija a causa com alcance proporcional

Priorize o menor conjunto de mudanças que elimine o trabalho indevido ou reduza o custo demonstrado. Considere limites de atualização, processamento incremental, consultas melhores, descarte de respostas obsoletas e limpeza do ciclo de vida, conforme a causa encontrada. Explique os tradeoffs de cache, debounce, virtualização ou redução de frequência antes de aplicá-los.

Preserve a utilidade das atualizações, os estados reais e as animações que comunicam informação. Não considere resolvido um travamento apenas porque os dados deixaram de atualizar ou a tela passou a ocultar o processamento. Mudanças de acessibilidade, como respeitar movimento reduzido, podem coexistir com uma experiência visual rica.

### 5. Demonstre o resultado e encerre

Repita o mesmo cenário em condições comparáveis, incluindo uma execução representativa com mais dados ou atividade concorrente quando isso fizer parte do problema. Valide também que a correção não duplicou ações, perdeu atualizações ou degradou navegação e seleção. Acrescente testes duráveis somente para a causa ou o comportamento que precisam de proteção.

Entregue: reprodução, evidências anteriores, causa confirmada ou hipóteses restantes, alterações realizadas, comparação após a correção e limitações da medição. Diferencie melhoria percebida de melhoria medida. A tarefa termina quando o problema delimitado está corrigido e suficientemente verificado, ou quando existe um bloqueio concreto de evidência ou acesso claramente descrito. Não prolongue a investigação com otimizações sem relação com o sintoma.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
- Fontes e conceitos: [referencias/fontes-e-conceitos.md](../../referencias/fontes-e-conceitos.md)
