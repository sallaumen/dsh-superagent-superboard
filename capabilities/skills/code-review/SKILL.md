---
name: "code-review"
title: "Code review independente e orientado a achados"
category: "qualidade"
default_mode: "revisar"
origem: ["P27"]
related: ["revisar-arquitetura", "estrategia-de-testes", "investigar-bugs", "validar-entrega"]
description: "Use para avaliar um diff, PR ou conjunto delimitado de mudanças antes da integração. Padrão somente leitura: reporta achados, não altera a implementação, não publica comentários nem aprova o PR sem autorização específica já presente na sessão."
---

# Code review independente e orientado a achados

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`revisar`). Uma instrução explícita da sessão prevalece.

## Quando usar

Para avaliar um diff, PR ou conjunto delimitado de mudanças antes da integração. O padrão é somente leitura: esta skill não autoriza implementar correções, publicar comentários ou aprovar um PR.

## Entradas úteis

- PR, intervalo de commits ou arquivos alterados. Se não estiver definido, identifique o diff disponível e confirme seu alcance pelo estado do repositório.
- Objetivo da mudança e restrições relevantes.
- Comandos de verificação ou evidências já produzidas pelo autor.

## Instrução

Faça um code review independente do escopo informado. Procure defeitos demonstráveis, regressões e riscos relevantes para o comportamento esperado. Trabalhe em modo de revisão: não altere a implementação nem publique comentários externos sem autorização específica já presente na sessão.

### Delimite o que está sendo revisado

Identifique base, alterações e contexto de trabalho. Não assuma que todos os arquivos modificados pertencem à mesma tarefa, nem descarte mudanças locais para preparar o review. Registre qual revisão ou diff foi efetivamente analisado.

Leia o objetivo declarado e as instruções do projeto. Entenda o problema que a mudança tenta resolver e os contratos que precisa preservar. Compare a descrição com o código, sem tratar a explicação do autor como prova de correção.

Leia os caminhos afetados e seus consumidores além das linhas do diff. Investigue dados, configurações, tarefas persistidas, usos dinâmicos e compatibilidade quando relevantes. Amplie a leitura para resolver um risco concreto, evitando uma auditoria indiscriminada de todo o repositório.

### Examine comportamento e consequências

Verifique regras de domínio, tratamento de erros, estados intermediários, identidade dos dados, autorização, isolamento e efeitos externos. Considere repetição, concorrência, ordem dos eventos, cancelamento, timeout e recuperação quando o fluxo puder enfrentá-los.

Avalie se a mudança funciona com registros anteriores e durante a coexistência de versões. Observe migrações, valores padrão, remoção de campos, cache e trabalhos já enfileirados. Uma compilação bem-sucedida não comprova compatibilidade operacional.

Inspecione a interface quando houver alteração visível: estados de carregamento e erro, ações disponíveis, acessibilidade básica, navegação e correspondência entre o que é mostrado e o que será executado. Não invente problemas de layout a partir do código se a conclusão depender de observar a tela.

Considere desempenho com base em volume e frequência plausíveis. Diferencie um custo demonstrável de uma otimização especulativa. Mudanças estilísticas ou preferências arquiteturais sem consequência concreta devem ser sugestões opcionais, separadas dos achados que bloqueiam a entrega.

### Verifique as evidências disponíveis

Leia os testes alterados e observe o que realmente afirmam. Procure expectativas enfraquecidas, mocks que escondem o risco e cobertura ausente para o comportamento novo. Não peça testes apenas porque um arquivo mudou; explique qual falha relevante precisa ser detectada.

Execute verificações proporcionais e não destrutivas quando o ambiente permitir. Não envie mensagens, crie pedidos ou modifique dados reais para confirmar um achado sem autorização. Se precisar de uma reprodução que altere arquivos, use uma cópia isolada e não incorpore mudanças ao trabalho do autor.

Informe o que executou e o que apenas inspecionou. Uma suíte verde é uma evidência limitada ao que ela verifica. Ausência de ambiente ou credenciais deve aparecer como limitação específica, sem ser convertida em certeza de defeito ou de correção.

### Produza achados acionáveis

Para cada achado, informe gravidade, localização precisa, condição que o dispara, consequência e evidência. Explique o comportamento esperado e a direção possível da correção sem exigir uma implementação arbitrária. Use exemplos mínimos e não exponha segredos nos trechos citados.

Ordene os achados por impacto e urgência. Separe problemas introduzidos ou agravados pela mudança de problemas preexistentes descobertos durante a leitura. Declare incertezas como hipóteses, acompanhadas do que falta verificar, em vez de apresentar especulação como bug confirmado.

Evite dividir a mesma causa em vários comentários redundantes. Se houver um problema estrutural que explica diferentes sintomas, descreva a causa e os pontos afetados de forma agrupada.

### Conclusão do review

Entregue primeiro os achados relevantes, depois dúvidas ou sugestões opcionais e, por fim, evidências e limitações. Se não encontrar defeitos justificáveis, diga isso claramente, sem fabricar observações para preencher o relatório.

Encerre com uma avaliação proporcional ao escopo: pronto para o próximo gate, precisa de correção ou depende de verificação específica. Não confunda essa avaliação técnica com aprovação formal, merge ou deploy, e não execute essas ações como consequência implícita do review.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
- Modelo de registro: [templates/registro-de-diagnostico.md](../../templates/registro-de-diagnostico.md)
