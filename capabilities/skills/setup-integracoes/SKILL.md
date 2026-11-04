---
name: "setup-integracoes"
title: "Refinar configuração de integrações e fornecedores"
category: "operacao"
default_mode: "analisar-e-corrigir"
origem: ["P21"]
related: ["contratos-e-dados", "ux-e-navegacao", "estados-assincronos", "elegibilidade-comercial", "assets-e-imagens", "seguranca-e-permissoes"]
description: "Use quando uma conta parece configurada, mas o usuário não entende o que falta para operar. Aplica-se a fornecedores, canais comerciais, pagamentos e outras integrações; a elegibilidade da oferta específica pertence a elegibilidade-comercial."
---

# Refinar configuração de integrações e fornecedores

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando uma conta parece configurada, mas o usuário não entende o que falta para operar. Aplica-se a fornecedores, canais comerciais, pagamentos e outras integrações, preservando as exigências próprias de cada serviço.

## Entradas úteis

- Integrações ou fluxos prioritários; sem uma lista, inventarie os existentes no escopo.
- Resultado esperado após o setup, como sincronizar catálogo ou solicitar uma amostra.
- Acesso autorizado a ambientes de teste e documentação oficial dos serviços.

## Instrução

Revise e refine o processo de configuração das integrações deste escopo. O usuário precisa entender o que já funciona, o que falta, por que falta e como continuar. Faça a investigação no código e nos fluxos reais; não presuma que salvar uma conta significa estar pronto para operar. Corrija de forma autônoma os problemas locais e reversíveis permitidos pelo modo da tarefa.

### 1. Descubra a prontidão de cada integração

Inventarie os serviços efetivamente implementados e suas capacidades observáveis. Diferencie integração existente, implementação parcial, função não suportada pelo provedor, configuração ausente e informação ainda não verificada. Não trate todas essas situações como um erro genérico de credenciais.

Mapeie as etapas que realmente se aplicam: dados salvos, autenticação válida, permissões necessárias, conta ou loja selecionada, recursos sincronizados e operação habilitada. Para fornecedores, a prontidão pode depender também de catálogo, variante, localidade e tipo de pedido. Determine quais verificações são locais, quais exigem consulta externa e por quanto tempo o resultado é confiável.

### 2. Transforme o setup em um caminho recuperável

Organize as etapas na ordem das dependências, reaproveitando os dados já fornecidos. Mostre uma próxima ação clara e permita retomar de onde parou. Evite um wizard rígido quando um painel de estados e ações resolver melhor; escolha o formato pela complexidade real. A interface deve continuar útil depois da primeira configuração, inclusive para renovação, mudança de conta e correção de falhas.

Explique o bloqueio no ponto da ação: o que falta, qual operação ele impede e como resolver. Não use textos longos para compensar estados ambíguos. Preserve campos válidos após erro e diferencie validação local de resposta do serviço. Ao verificar uma conexão, represente solicitação recebida, verificação em curso e resultado confirmado sem mostrar sucesso antecipado.

### 3. Mapeie ajuda contextual confiável

Para cada integração do escopo, confira links oficiais relevantes: documentação, painel da conta, obtenção ou gestão de credenciais, permissões, catálogo, requisitos técnicos e suporte, conforme o serviço. Registre o destino e sua finalidade em uma fonte reutilizável, compatível com a arquitetura existente. Não espalhe cópias inconsistentes em componentes.

Apresente cada link próximo da tarefa que ele ajuda a concluir. Não invente URLs nem use links de terceiros como documentação oficial. Não inclua tokens, chaves ou dados privados em URLs. Se não for possível verificar um destino, marque a lacuna no relatório e mantenha apenas alternativas comprovadas. Registre também limites reais do conector para evitar que a UI prometa uma função não implementada.

### 4. Reforce o contrato entre backend e interface

Substitua booleanos ambíguos por um modelo de estado suficiente para explicar a prontidão, se a análise demonstrar necessidade. Evite uma estrutura genérica tão extensa que elimine diferenças relevantes entre provedores. Separe metadados estáveis de resultados de verificações, credenciais e erros operacionais.

Considere expiração, revogação, troca de conta, sincronização parcial e respostas atrasadas. Uma verificação antiga não pode validar uma credencial recém-alterada. Proteja operações repetidas contra duplicação quando houver efeito persistente. Diagnóstico deve ser possível sem expor segredos em respostas, logs ou capturas. Consulte a documentação oficial para detalhes de APIs e versões que não estejam demonstrados no repositório.

### 5. Valide o uso completo

Exercite ao menos o caminho coerente com os riscos encontrados: configuração nova, configuração já existente, falha recuperável e retorno ao fluxo que estava bloqueado. Confirme que a pessoa consegue descobrir sozinha a próxima ação. Teste também a apresentação em tela pequena e grande quando o setup ocupar páginas ou painéis extensos.

Use ambientes ou respostas controladas para operações que gerem custo, pedidos ou alterações externas não autorizadas. Entregue a matriz de capacidades e prontidão, o mapa de links verificados, as mudanças implementadas e as evidências do fluxo. A tarefa termina quando a configuração leva a um estado operacional compreensível e verificável, ou quando um limite externo real está claramente explicado com a ação necessária para avançar.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
