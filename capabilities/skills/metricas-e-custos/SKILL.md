---
name: "metricas-e-custos"
title: "Revisar métricas, custos e proveniência dos números"
category: "operacao"
default_mode: "analisar-e-corrigir"
origem: ["P24"]
related: ["contratos-e-dados", "estados-assincronos", "orquestracao-ias", "elegibilidade-comercial", "alertas-operacionais", "simulacao-e-producao"]
description: "Use quando painéis exibem totais pouco explicáveis, custos de IA ou operações misturados, ausência de dados tratada como zero ou medidas de escopos diferentes comparadas como equivalentes. Cada indicador precisa de significado, origem e limitações visíveis."
---

# Revisar métricas, custos e proveniência dos números

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando painéis exibem totais pouco explicáveis, custos de IA ou operações misturados, ausência de dados tratada como zero ou medidas de escopos diferentes comparadas como equivalentes. Não é uma auditoria contábil; trata os contratos e a apresentação de métricas do produto.

## Entradas úteis

- Painel ou indicador prioritário e a decisão que ele deveria apoiar.
- Fontes de uso, preços, cobrança e registros operacionais disponíveis.
- Período, ambiente, moedas e níveis de agregação relevantes, se já definidos.

## Instrução

Revise e corrija a confiabilidade dos números exibidos neste escopo. Quero que cada indicador tenha um significado claro, uma origem verificável e limitações visíveis. Descubra o caminho completo entre o evento e o painel. Respeite o modo da tarefa e não apresente uma estimativa técnica como confirmação de cobrança ou resultado financeiro.

### 1. Defina o significado antes da fórmula

Para cada indicador prioritário, registre a pergunta que ele responde, a unidade, a fonte, o período, o fuso horário e as dimensões de agregação. Diferencie contagem de eventos, trabalhos únicos, tentativas, itens processados, capacidade disponível e consumo efetivo. Um limite configurado não equivale a uso; uma cota restante não equivale a saldo monetário.

Identifique escopos de conta, projeto, loja, fornecedor, ambiente e execução. Verifique se filtros alteram corretamente todos os componentes relacionados ou apenas parte do painel. Quando houver comparação temporal, confira períodos equivalentes e o tratamento de janelas ainda incompletas. Não acrescente indicadores apenas porque os dados estão acessíveis.

### 2. Verifique proveniência e completude

Siga os registros de origem, transformações, agregações e caches. Procure duplicação por retries, eventos recebidos mais de uma vez, junções que multiplicam linhas e registros atrasados. Diferencie ausência de atividade de ausência de medição, falha de coleta e cobertura parcial. Zero deve representar uma quantidade conhecida, não uma substituição conveniente para informação desconhecida.

Decida como expor atualidade e completude sem sobrecarregar a interface. Preserve evidências suficientes para explicar um total por componentes e localizar discrepâncias. Uma métrica reconstruída a partir de logs pode ter limites diferentes de uma fonte oficial; documente essa diferença e evite precisão que a origem não sustenta.

### 3. Trate custos com unidades e regras explícitas

Separe consumo medido, preço aplicado, custo estimado, cobrança confirmada e ajustes, quando essas categorias existirem. Para serviços de IA ou outros provedores, verifique as unidades e regras efetivamente contratadas, incluindo categorias de uso relevantes. Consulte fontes oficiais atuais quando for necessário obter preços ou interpretar a API; não use valores lembrados como verdade permanente.

Associe a regra de preço ao período e à origem usados no cálculo. Não some moedas diferentes como se fossem a mesma. Quando houver conversão, explicite taxa, data e caráter estimado. Revise arredondamento e precisão nas etapas apropriadas, sem prescrever uma tecnologia incompatível com a stack. Falha de coleta de uso não torna uma operação gratuita.

### 4. Corrija a agregação e a apresentação

Centralize definições compartilhadas quando a dispersão gerar divergência, preservando diferenças legítimas entre métricas. Defina identificação e deduplicação proporcionais ao evento: uma nova tentativa pode ser duplicação de notificação e, ao mesmo tempo, consumo real adicional. Não remova custo verdadeiro apenas para fazer os totais coincidir.

Apresente o número principal com unidade e contexto suficientes; detalhes, composição e fonte podem ficar em expansão ou navegação contextual. Diferencie simulação e produção, estimativa e confirmação, valor parcial e completo. Cores e ícones podem ajudar, mas o significado não deve depender exclusivamente deles. Evite gráficos decorativos que obscureçam o valor ou comparação solicitados.

### 5. Reconcilie e demonstre

Escolha um conjunto pequeno de operações conhecidas e recompute os indicadores a partir das fontes. Inclua os riscos encontrados, como retry, evento atrasado, fronteira de período, moeda diferente ou dado ausente. Compare cálculo, persistência e interface no mesmo escopo. Acrescente testes para fórmulas e invariáveis relevantes, sem duplicar toda a implementação em expectativas mecânicas.

Entregue um dicionário dos indicadores revisados, exemplos de reconciliação, defeitos confirmados, correções e limitações restantes. Se uma fonte não estiver disponível, deixe o indicador explicitamente incompleto e descreva a integração necessária. A tarefa termina quando os números prioritários podem ser explicados e reproduzidos a partir de evidências, e sua apresentação não promete certeza maior do que a medição permite.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
