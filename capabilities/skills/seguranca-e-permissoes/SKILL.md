---
name: "seguranca-e-permissoes"
title: "Revisar segurança, permissões e isolamento de dados"
category: "qualidade"
default_mode: "analisar-e-corrigir"
origem: ["P29"]
related: ["contratos-e-dados", "setup-integracoes", "code-review", "migracoes-e-compatibilidade", "simulacao-e-producao"]
description: "Use ao revisar um fluxo que lê ou altera dados sensíveis, integra contas externas, usa ferramentas de IA ou atende múltiplas organizações. Foco em falhas concretas de autorização, isolamento, entradas e segredos; não autoriza testes ofensivos contra terceiros."
---

# Revisar segurança, permissões e isolamento de dados

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Ao revisar um fluxo que lê ou altera dados sensíveis, integra contas externas, usa ferramentas de IA ou atende múltiplas organizações. Esta skill não autoriza testes ofensivos contra sistemas de terceiros.

## Entradas úteis

- Fluxo, perfis de acesso e limites de ambiente ou organização.
- Ameaça ou incidente observado, quando houver; caso contrário, derive os riscos do fluxo real.

## Instrução

Revise a segurança do escopo indicado com foco em falhas concretas de autorização, isolamento, tratamento de entradas e exposição de dados. Corrija problemas locais comprovados e compatíveis com o objetivo. Evite transformar a revisão em uma lista genérica de recomendações ou em uma reescrita de autenticação sem necessidade.

### Mapeie confiança e acesso

Identifique atores, credenciais, recursos protegidos, fronteiras de confiança e efeitos de cada operação. Registre onde a identidade é autenticada, onde permissões são verificadas e quais camadas podem executar a mesma ação: UI, endpoints, jobs, webhooks, administração e ferramentas de agentes. Um botão escondido não substitui autorização no ponto que altera ou entrega o dado.

Se houver organizações, lojas, marcas, projetos ou ambientes, siga seus identificadores desde a entrada até consultas, caches, filas e integrações. Procure situações em que o usuário controla um identificador sem que o vínculo com o recurso seja validado. Considere leituras e alterações, inclusive exportações, anexos e URLs de mídia.

Examine o caminho dos segredos. Procure vazamentos em logs, mensagens de erro, artefatos, respostas ao cliente e configurações versionadas, sem copiar valores sensíveis para o relatório. Diferencie configuração necessária de um segredo realmente exposto. Se encontrar exposição, indique o tipo, localização e necessidade de rotação; não faça rotação de credenciais de produção sem autorização específica.

### Investigue os riscos do comportamento encontrado

Priorize controles ausentes ou inconsistentes: acesso a recursos de outra conta, autorização perdida em jobs, verificação insuficiente de webhooks, reenvio de operações, construção insegura de consultas ou comandos, tratamento de arquivos e destinos de rede controlados pelo usuário. Verifique somente os vetores pertinentes à stack e ao fluxo, consultando documentação oficial quando o comportamento de um framework for decisivo.

Em funcionalidades com IA, trate documentos, mensagens externas e resultados de ferramentas como dados sem autoridade para mudar permissões. Examine quem pode fornecer instruções, quais ferramentas o agente consegue acionar e como uma ação com efeito real é autorizada. Limitar o texto de um prompt não substitui controles nos serviços que executam a operação.

Para cada achado, descreva precondições, caminho afetado, efeito possível, evidência e confiança. Não apresente um padrão suspeito como vulnerabilidade confirmada sem demonstrar sua alcançabilidade. Diferencie gravidade do impacto e certeza do diagnóstico.

### Corrija no ponto que garante a regra

Prefira corrigir a fronteira de autorização, o contrato de entrada ou o isolamento de dados, evitando remendos apenas visuais. Preserve usuários legítimos, fluxos de suporte e mecanismos de recuperação. Reuse controles existentes quando forem adequados; se precisar centralizar uma política, mantenha explícitas as exceções de domínio.

Não faça exploração em produção, varreduras externas, criação de contas, envio de mensagens ou extração de dados como parte implícita desta revisão. Use o código, ambiente local e dados de teste autorizados para demonstrar o comportamento. Se uma verificação depende de outro ambiente, deixe o procedimento e o limite claros.

### Valide e conclua

Escolha casos que demonstrem a regra: operação válida, recurso de outra organização, perfil sem permissão e entrada inválida relevante. Inclua caminhos alternativos que contornariam a UI. Não adicione dezenas de testes idênticos quando um contrato comum protege o mesmo comportamento; mantenha testes separados quando as fronteiras forem distintas.

Entregue achados priorizados, correções, pontos ainda incertos e evidências de validação. Redija exemplos com dados fictícios e sem segredos. Explique qualquer risco residual ou dependência de configuração externa. Conclua quando os problemas do recorte estiverem tratados e os acessos legítimos preservados, ou quando a limitação de acesso impedir uma afirmação responsável. Não apresente esta revisão delimitada como certificação completa de segurança.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
