---
name: "consolidar-codigo"
title: "Consolidação de código inacabado, obsoleto ou sem uso"
category: "arquitetura"
default_mode: "analisar-e-corrigir"
origem: ["P06"]
related: ["coordenar-entregas", "revisar-arquitetura", "organizar-modulos", "testes-redundantes"]
description: "Use quando há funcionalidades pela metade, caminhos abandonados, stubs ou implementações concorrentes que tornam o produto confuso. Para coordenar essa consolidação em várias áreas, use coordenar-entregas como entrada."
---

# Consolidação de código inacabado, obsoleto ou sem uso

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando há funcionalidades pela metade, caminhos abandonados, stubs ou implementações concorrentes que tornam o produto confuso. Para coordenar essa consolidação em várias áreas, utilize coordenar-entregas como entrada.

## Entradas úteis

- Área ou fluxo a consolidar e objetivo atual do produto.
- Planos antigos, relatos de uso ou restrições conhecidas, tratados como evidência a conferir.
- Preferência explícita por concluir, simplificar ou retirar alguma funcionalidade, se existir.

## Instrução

Investigue o escopo informado e consolide o que estiver incompleto, abandonado ou incoerente com o produto atual. Uma ideia antiga pode ser concluída, simplificada, substituída ou retirada. Quero um resultado que faça sentido para quem usa e mantém o sistema, com menos caminhos ambíguos e funcionalidades que realmente terminam.

### Descubra o estado real de cada candidato

Percorra a interface e o código dos fluxos relevantes. Considere TODOs, stubs, exceções genéricas, implementações paralelas, flags, rotas sem saída e documentação antiga como pistas de investigação. Não trate qualquer uma dessas pistas, isoladamente, como prova de abandono.

Para cada candidato, identifique intenção original, comportamento disponível, consumidores, dados associados, dependências e evidência de uso. Diferencie implementação incompleta de configuração ausente, funcionalidade deliberadamente limitada, recurso desativado por operação e integração indisponível.

Examine também caminhos dinâmicos e indiretos: tarefas agendadas, callbacks, plugins, comandos administrativos, contratos externos e referências persistidas. Ausência de chamadas textuais ou de tráfego em uma amostra curta não comprova ausência de uso.

### Julgue utilidade e coerência

Avalie o que a funcionalidade acrescenta ao produto atual, quanto falta para entregar valor e qual custo permanente ela introduz. Uma promessa na documentação não obriga implementar toda a ideia. Da mesma forma, uma implementação feia pode atender uma necessidade importante que merece ser preservada.

Classifique cada decisão proposta como concluir, simplificar, unificar, retirar, manter conscientemente ou adiar. Explique o motivo e o resultado esperado para o usuário. Priorize problemas que geram dados inconsistentes, ações sem conclusão, navegação confusa ou manutenção recorrente.

Resolva autonomamente questões técnicas reversíveis com evidência suficiente. Quando duas opções alterarem de forma relevante o produto ou retirarem uma capacidade ainda utilizada, apresente uma pergunta simples, duas ou três alternativas e sua recomendação. Prepare o diagnóstico e as consequências antes de perguntar; continue o trabalho independente enquanto aguarda.

### Faça a limpeza completa do fluxo

Escolha um conjunto pequeno e coerente de candidatos. Defina o estado final, os consumidores afetados e a condição de término antes de começar. Evite abrir mais funcionalidades do que consegue concluir nesta rodada.

Ao concluir uma ideia, entregue o caminho utilizável de ponta a ponta: entrada, regra, persistência, retorno, estados de falha e possibilidade de recuperação, conforme aplicável. Remover uma mensagem de pendência ou preencher um stub com valor fixo não torna o fluxo concluído.

Ao simplificar ou unificar, escolha uma fonte de verdade e migre os consumidores. Não deixe duas soluções permanentes com resultados diferentes. Ao retirar código, atualize pontos de entrada, links, configuração, documentação e testes que existiam exclusivamente para aquele comportamento.

Retirar uma funcionalidade não significa apagar dados históricos, revogar contratos externos ou destruir a possibilidade de consultar resultados anteriores. Identifique retenção, compatibilidade, reversão e migrações necessárias. Operações destrutivas dependem do escopo e da autorização concretos; a limpeza de código não os substitui.

### Verifique consequências e evite falsa limpeza

Valide os fluxos preservados e os caminhos de acesso ao que mudou. Verifique se tarefas antigas, links existentes ou registros anteriores produzem uma resposta definida. Não esconda erros removendo testes, desativando validações ou transformando estados desconhecidos em sucesso.

Quando a retirada depender de confirmar uso externo, registre a limitação e implemente somente a etapa segura disponível. Não afirme que uma funcionalidade está sem uso em produção sem evidência suficiente.

### Entrega e encerramento

Entregue um inventário curto com estado observado, decisão, justificativa e resultado de cada candidato tratado. Mostre o que passou a funcionar, o que foi simplificado e quais entradas foram removidas. Inclua evidências de validação e pendências concretas.

Conclua quando os candidatos escolhidos tiverem um destino implementado ou um bloqueio específico documentado, e os fluxos restantes continuarem coerentes. Uma lista longa de TODOs reclassificados não substitui a consolidação efetiva do recorte.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
