---
name: "contratos-e-dados"
title: "Contratos, fontes de verdade e integridade de dados"
category: "arquitetura"
default_mode: "analisar-e-corrigir"
origem: ["P08"]
related: ["revisar-arquitetura", "versoes-e-rastreabilidade", "estados-assincronos", "migracoes-e-compatibilidade"]
description: "Use quando frontend, backend, banco e integrações discordam sobre dados ou estados, existem duplicações de regras ou uma operação deixa registros incoerentes. Para uma migração já decidida, aprofunde com migracoes-e-compatibilidade."
---

# Contratos, fontes de verdade e integridade de dados

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando frontend, backend, banco e integrações discordam sobre dados ou estados, existem duplicações de regras ou uma operação deixa registros incoerentes. Para uma migração já decidida, aprofunde com migracoes-e-compatibilidade.

## Entradas úteis

- Fluxo, entidade ou inconsistência a investigar.
- Exemplos de registros ou respostas, sem segredos ou dados pessoais desnecessários.
- Consumidores e requisitos de compatibilidade conhecidos.

## Instrução

Revise os contratos e a integridade dos dados no escopo informado. Quero que decisões, registros e informações apresentadas tenham significado consistente, com proprietários claros e tratamento explícito de falhas, repetição e concorrência.

### Acompanhe os dados ao longo do fluxo

Mapeie quem cria, transforma, valida, persiste, consulta e apresenta cada informação relevante. Identifique a fonte de verdade, cópias derivadas, caches, snapshots e dados vindos de terceiros. Observe o comportamento implementado, e não apenas os tipos declarados ou a documentação.

Examine as fronteiras entre contextos, API, tarefas, banco e interface. Registre identidades, formatos, unidades, moeda, fuso, cardinalidade e escopo quando influenciarem o significado. Verifique se um identificador pertence à conta, loja, organização ou ambiente esperado antes de ser usado.

Separe ausente, desconhecido, pendente, vazio, zero, inválido e não aplicável quando essas diferenças alterarem decisões. Um valor padrão conveniente não pode transformar informação indisponível em confirmação de que algo está correto.

### Explicite contratos e invariantes

Para cada operação importante, descreva entrada aceita, saída, erros, efeitos e garantias. Determine quais regras pertencem ao domínio, quais dependem de um provedor e quais são apenas apresentação. Procure validações duplicadas que já divergem e regras existentes somente no cliente.

Identifique invariantes que precisam sobreviver a qualquer ponto de entrada, inclusive tarefas e integrações. Escolha o lugar adequado para garanti-las: domínio, transação, restrição de banco, autorização ou contrato externo. Não replique a mesma política em todas as camadas sem propósito; validação de interface pode orientar o usuário sem se tornar a única proteção.

Examine como estados transitam e quem tem autoridade para confirmá-los. “Pedido recebido”, “em execução” e “concluído” podem representar fatos distintos. Uma atualização local ou resposta aceita por terceiro não comprova a conclusão do efeito final.

### Investigue falhas de coordenação

Procure operações parcialmente gravadas, duplicação por retry, eventos fora de ordem, leitura de cache antigo e decisões feitas sobre informação que mudou. Determine onde consistência imediata é necessária e onde atraso é aceitável, com visibilidade e reconciliação adequadas.

Analise idempotência por operação e significado do negócio. Repetir uma requisição deve reutilizar o resultado quando apropriado; não deve bloquear uma segunda operação legítima apenas porque os dados parecem semelhantes. Verifique o comportamento quando o cliente recebe timeout e o servidor já concluiu a ação.

Considere exclusão, mudança de proprietário, alteração de catálogo e referências históricas. Distinga invalidar uma possibilidade futura de reescrever um fato passado. Não aplique correções em massa a dados reais sem delimitar a regra, a evidência e a autorização necessária.

### Corrija o menor conjunto coerente

Priorize inconsistências demonstradas pelo impacto no usuário e na confiabilidade. No modo de correção, ajuste contratos e consumidores em uma sequência compatível. Atualize esquemas, serialização, validações, respostas e tratamento da interface apenas na medida necessária para fechar o fluxo escolhido.

Se consumidores de versões diferentes puderem coexistir, planeje expansão e retirada de campos ou estados. Não considere um contrato migrado apenas porque o frontend atual foi atualizado. Identifique jobs persistidos, integrações e leitores anteriores que ainda possam circular.

Use nomes e representações que expressem o significado do domínio. Evite compensar inconsistências estruturais com conversões espalhadas ou valores mágicos. Quando houver dado legado ambíguo, preserve a ambiguidade e ofereça um caminho de saneamento verificável.

### Evidência e encerramento

Valide casos de sucesso, entrada inválida, escopo indevido, repetição e falha parcial conforme o risco do recorte. Exercite fronteiras reais suficientes para verificar persistência e contratos; mocks isolados não demonstram integridade entre componentes.

Entregue o mapa de fontes e consumidores, as invariantes adotadas, as divergências encontradas e as correções. Inclua exemplos de contratos antes e depois e o estado de compatibilidade. Diferencie dados observados, hipóteses e validações efetivamente executadas.

Encerre quando os fluxos escolhidos mantiverem suas invariantes e produzirem estados interpretáveis pelos consumidores. Registre saneamentos ou integrações inacessíveis como pendências concretas, sem declarar a base inteira íntegra a partir de uma amostra limitada.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
