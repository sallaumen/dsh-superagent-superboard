---
name: "orquestracao-ias"
title: "Refinar orquestração de IAs, capacidade e filas"
category: "operacao"
default_mode: "analisar-e-corrigir"
origem: ["P19"]
related: ["revisar-arquitetura", "contratos-e-dados", "estados-assincronos", "metricas-e-custos", "simulacao-e-producao"]
description: "Use quando jobs, workers, agentes e limites de IA estão misturados, a capacidade exibida não corresponde ao uso real ou a visualização operacional precisa representar o sistema com fidelidade. Trata contrato e operação; a direção artística pertence ao contexto visual do projeto."
---

# Refinar orquestração de IAs, capacidade e filas

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando jobs, workers, agentes e limites de IA estão misturados, a capacidade exibida não corresponde ao uso real ou a visualização operacional precisa representar o sistema com fidelidade. Esta skill trata o contrato e a operação; a direção artística pertence ao contexto visual do projeto.

## Entradas úteis

- Processos e serviços de IA no escopo, se conhecidos.
- Limites desejados e seus níveis: projeto, conta, provedor, funcionalidade ou fila.
- Visualização operacional existente e ambiente em que é possível validar concorrência.

## Instrução

Investigue e refine a forma como este projeto agenda processos, utiliza inteligências artificiais e representa essa atividade. Quero uma arquitetura que controle a capacidade real e uma interface coerente com o que está acontecendo. Descubra os mecanismos existentes e as versões utilizadas antes de propor alterações. Respeite o modo de trabalho definido na sessão.

### 1. Separe conceitos que hoje possam estar misturados

Mapeie filas, jobs, workers, chamadas a modelos, agentes, sessões e recursos disponíveis. Identifique o que cada limite controla. A quantidade de jobs em execução não deve ser tratada automaticamente como a quantidade de IAs ocupadas. Um processo pode aguardar rede, executar uma etapa comum ou delegar trabalho sem consumir a mesma capacidade durante todo o seu ciclo.

Determine quais recursos são globais ou compartilhados e quais pertencem a um ambiente, conta, provedor ou funcionalidade. Registre onde existem limites sobrepostos e quem tem autoridade para conceder capacidade. Procure caminhos que contornam o controle principal, incluindo tarefas agendadas, retries e processos filhos.

### 2. Descreva a necessidade de IA explicitamente

Proponha um contrato de metadados compatível com a stack para classificar processos que não usam IA, que sempre usam, que usam condicionalmente ou que delegam etapas com IA. Separe a capacidade declarada do processo do uso observado em uma execução específica. Informação ausente deve permanecer desconhecida até ser verificada; não a converta silenciosamente em ausência de IA.

Localize os consumidores desse contrato e evite manter listas manuais divergentes em backend e frontend. A declaração precisa orientar apresentação e diagnóstico, mas não deve substituir a evidência da alocação real. Se houver processos compostos, defina como representar o conjunto sem contar o mesmo recurso no pai e no filho.

### 3. Torne a alocação consistente

Revise reserva, aquisição, uso, liberação, expiração e recuperação após falha. Considere concorrência entre executores, reinícios, timeout, cancelamento e retry. Verifique se um trabalho abandonado retém capacidade e se duas execuções podem acreditar que possuem a mesma unidade. Escolha uma estratégia compatível com o ambiente distribuído efetivamente existente, sem criar infraestrutura desnecessária.

Defina o comportamento ao reduzir um limite abaixo do uso atual: impedir novas concessões, aguardar drenagem ou cancelar apenas quando essa política estiver explicitamente autorizada. Não confunda pausa da entrada de novos trabalhos, suspensão visual, cancelamento de uma tarefa e indisponibilidade de um provedor. Avalie espera excessiva ou monopolização de capacidade quando houver evidência no fluxo.

### 4. Exponha um modelo operacional verdadeiro

Forneça estados e relacionamentos que a interface consiga consumir: capacidade conhecida, reservada, ativa, liberada, pendente ou incerta, conforme o domínio. Inclua identificadores de correlação e dados suficientes para abrir detalhes de um processo sem expor credenciais ou conteúdo sensível. Mostre a idade da informação quando ela deixar de ser confiável.

Se a interface usar personagens, trajetos ou outras metáforas, a animação deve seguir transições observadas. Seu término não pode liberar recursos nem bloquear o agendador. Uma mesma unidade reutilizada rapidamente não pode aparecer como duas unidades simultâneas. Processos sem IA continuam visíveis e importantes, com uma linguagem visual distinta que não dependa apenas de cor.

### 5. Verifique os limites e conclua

Implemente incrementos pequenos que conectem contrato, controle de capacidade e observação. Exercite os cenários pertinentes: concorrência no limite, trabalho sem IA, etapa condicional, retry, falha do executor, redução de capacidade e reconexão do painel. Use simulação ou serviços controlados quando a chamada real gerar custo ou efeito não autorizado.

Entregue o modelo anterior e o implementado, as invariáveis protegidas, as políticas escolhidas e as evidências de execução. Indique separadamente a configuração permitida e o uso efetivamente medido. A entrega termina quando os caminhos do escopo obedecem aos mesmos limites e a visualização pode explicar a ocupação sem inventar atividade. Dependências ou caminhos não cobertos devem ficar explicitamente registrados.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
