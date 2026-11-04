---
name: "alertas-operacionais"
title: "Refinar alertas operacionais e seu ciclo de vida"
category: "operacao"
default_mode: "analisar-e-corrigir"
origem: ["P33"]
related: ["contratos-e-dados", "ux-e-navegacao", "estados-assincronos", "notificacoes-e-bots", "metricas-e-custos"]
description: "Use quando um painel acumula avisos repetidos, mistura problemas atuais com histórico ou trata marcar como visto como solução. O foco é o problema operacional e sua resolução; o envio por bot, email ou outro canal pertence a notificacoes-e-bots."
---

# Refinar alertas operacionais e seu ciclo de vida

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando um painel acumula avisos repetidos, mistura problemas atuais com histórico ou trata marcar como visto como solução. O foco é o problema operacional e sua resolução; o envio por bot, email ou outro canal pertence ao fluxo de notificações.

## Entradas úteis

- Área que concentra alertas e tipos de incidente mais frequentes.
- Fontes que detectam falha e recuperação, quando conhecidas.
- Ações operacionais disponíveis e a autoridade necessária para executá-las.

## Instrução

Revise e refine a detecção, organização e resolução dos alertas operacionais deste escopo. O usuário precisa reconhecer o que exige ação agora, entender o impacto e chegar ao lugar certo para resolver. Investigue o ciclo de vida no backend e na interface antes de reorganizar o painel. Implemente as correções locais permitidas pelo modo da tarefa.

### 1. Separe evento, problema e notificação

Mapeie quem produz os eventos, quem decide que existe um problema, como ele é persistido e onde é apresentado. Diferencie um evento isolado, um incidente em andamento, uma informação de histórico e uma mensagem enviada ao usuário. A repetição de um evento não precisa criar um novo cartão, mas sua frequência pode ser relevante para explicar a gravidade.

Identifique a condição de abertura e a evidência de recuperação de cada classe prioritária. Determine se o problema é atual, histórico, ainda não verificado ou consequência de outro incidente. Não resolva um alerta apenas porque parou de receber eventos; o detector também pode ter ficado indisponível. Da mesma forma, não mantenha um problema ativo quando existe confirmação suficiente de recuperação.

### 2. Modele um ciclo de vida compreensível

Distinga estado operacional e tratamento humano. Visto, reconhecido, adiado e silenciado não significam que a causa foi corrigida. Defina como essas decisões afetam apresentação e notificações, sem apagar o fato operacional. Preserve data da primeira ocorrência, última evidência, frequência e mudanças relevantes quando esses dados forem necessários para diagnóstico.

Revise reabertura, recorrência e agrupamento. Uma chave de agrupamento deve respeitar tipo, entidade, conta e ambiente pertinentes, evitando juntar falhas de lojas ou serviços diferentes. Não crie uma entidade permanente sem necessidade; escolha o modelo mais simples que preserve o ciclo real e permita responder o que ainda está acontecendo.

### 3. Organize por impacto e ação

Classifique prioridades com critérios que o domínio consiga justificar: operação bloqueada, usuários afetados, prazo, persistência ou risco de perda, por exemplo. Não transforme qualquer erro técnico em alerta crítico. Diferencie problema acionável de informação e deixe claro quando a recuperação é automática ou depende de uma ação externa.

Para cada alerta prioritário, apresente uma frase concreta sobre o problema e uma ação contextual. Leve à configuração, processo, produto ou registro correto, preservando ambiente e identidade. Evite botões genéricos que fazem o usuário procurar novamente a origem. Detalhes técnicos e histórico podem aparecer sob demanda; a página principal deve permitir decidir o que fazer sem ler blocos extensos.

### 4. Corrija coleta, reconciliação e ruído

Procure duplicação entre detectores, reprocessamento após reinício, contagens acumuladas incorretas e notificações sobre a própria falha de notificação. Defina identidades e transições que tolerem eventos duplicados ou atrasados. Se o painel depender de tempo real, confira também sua recuperação após recarregar e reconectar.

Estabeleça quando reconciliar o alerta com o estado de origem e como representar informação desatualizada. Silenciamento deve ter um escopo claro e, quando adequado, uma duração; não o transforme em remoção silenciosa de toda uma classe de problemas. Ações de correção devem refletir o que realmente executam e manter as autorizações necessárias para efeitos externos ou destrutivos.

### 5. Verifique os ciclos completos

Exercite abertura, repetição, reconhecimento, recuperação e recorrência dos problemas modificados. Inclua eventos fora de ordem ou indisponibilidade do detector quando forem riscos encontrados. Confirme que o agrupamento não mistura entidades e que um usuário consegue alcançar a ação correta. Testes de transição devem proteger essas regras; capturas do painel, sozinhas, não comprovam o ciclo operacional.

Entregue o mapa dos estados, os critérios de prioridade e agrupamento, as mudanças e as evidências dos ciclos validados. Explique o que os contadores representam e quais alertas ainda dependem de uma fonte externa. Conclua quando o painel distingue claramente problemas atuais de histórico, reduz repetições sem ocultar impacto e só apresenta resolução quando existe evidência compatível com o contrato definido.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
