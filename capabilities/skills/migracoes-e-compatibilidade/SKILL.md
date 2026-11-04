---
name: "migracoes-e-compatibilidade"
title: "Planejar e corrigir migrations e compatibilidade entre versões"
category: "qualidade"
default_mode: "analisar-e-corrigir"
origem: ["P30"]
related: ["coordenar-entregas", "organizar-modulos", "versoes-e-rastreabilidade", "contratos-e-dados", "validar-entrega"]
description: "Use ao alterar esquema, identificadores, módulos persistidos, payloads de jobs, contratos públicos ou qualquer dado que precise sobreviver à troca de versão. Não se limita a migrations SQL; preparação não autoriza operações destrutivas em produção."
---

# Planejar e corrigir migrations e compatibilidade entre versões

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Ao alterar esquema, identificadores, módulos persistidos, payloads de jobs, contratos públicos ou qualquer dado que precise sobreviver à troca de versão. Não se limita a migrations SQL.

## Entradas úteis

- Alteração pretendida, tipos e volumes aproximados de dados, política de deploy.
- Consumidores antigos e requisitos de retenção ou reversão conhecidos.

## Instrução

Revise a mudança indicada para que código, dados e consumidores continuem compatíveis durante sua implantação. Implemente as adaptações e migrations locais necessárias, em etapas verificáveis. A preparação desta mudança não autoriza executar operações destrutivas ou migrations em produção.

### Descubra o que precisa sobreviver

Mapeie o contrato atual e o proposto: esquema, valores permitidos, identificadores, formatos serializados, eventos, caches, URLs públicas e nomes persistidos. Procure consumidores em código, jobs já enfileirados, agendamentos, integrações, exportações e registros históricos. Uma função renomeada pode continuar referenciada em dados; uma busca textual no código não resolve essa possibilidade sozinha.

Entenda a política de deploy e rollback. Verifique se versões antigas e novas podem executar ao mesmo tempo, se workers vivem mais que a requisição e se tarefas longas atravessam uma implantação. Identifique o momento em que uma mudança deixa de ser reversível apenas com o retorno do código anterior.

Inspecione volumes e distribuição de dados com meios autorizados. Trabalhe com amostras ou estimativas explícitas quando não houver acesso real. Não anuncie uma migration como rápida ou segura em produção apenas porque funcionou em uma base vazia.

### Defina uma sequência compatível

Escolha a menor estratégia que permita evolução segura. Quando houver coexistência, considere uma sequência de expansão do contrato, adaptação de consumidores, preenchimento de dados e retirada posterior do formato antigo. Quando não houver esse requisito, não acrescente mecanismos temporários sem benefício demonstrável.

Defina invariantes antes, durante e depois: unicidade, referências, isolamento por organização, unidades, versões e estados válidos. Especifique como tratar registros antigos, inconsistentes ou sem informação suficiente. Não invente valores de negócio para satisfazer uma coluna obrigatória; preserve a incerteza ou peça a decisão necessária.

Avalie operações que podem bloquear tabelas, aumentar carga, processar grandes lotes ou disputar escrita com a aplicação. Proponha limites, checkpoints e retomada quando o volume justificar. Para backfills, explique como evitar duplicação e como identificar progresso parcial. Não imponha um mecanismo específico de banco sem verificar a versão e a documentação aplicáveis.

### Implemente e preserve rastreabilidade

Separe a mudança de contrato da limpeza que só pode ocorrer depois de todos os consumidores migrarem. Registre condições objetivas para remover compatibilidade temporária. Preserve a identidade e a história dos registros quando renomear ou reorganizar entidades.

Trate erros intermediários como parte do fluxo. Uma interrupção não deve deixar o sistema sem saber quais registros foram migrados. Mantenha auditável a transformação relevante, sem duplicar dados sensíveis desnecessariamente.

Se a mudança exigir apagar ou reinterpretar dados de forma irreversível, prepare o plano, estimativa de impacto e validações antes de solicitar uma decisão. Não use a palavra rollback para uma reversão que perde informações ou não desfaz efeitos externos.

### Valide as transições reais

Teste com dados representativos das regras afetadas: registros novos, legados, incompletos e casos de interrupção. Verifique leitores e escritores durante a coexistência quando ela for necessária. Confirme que jobs antigos ainda podem ser processados ou recebem tratamento explícito.

Compare contagens e invariantes relevantes antes e depois. Valide retomada de backfill se implementada, sem usar repetição destrutiva como teste. Execute somente os comandos permitidos no ambiente autorizado. Simulação e dry run não substituem verificação após execução real.

### Entrega

Apresente a sequência de implantação, dependências, invariantes, mudanças locais, verificações realizadas, limites de reversão e condições de limpeza futura. Inclua o procedimento de acompanhamento para quem executar a migration no ambiente final. Conclua com a preparação validada no escopo autorizado; indique separadamente o que ainda depende de execução, volume ou observação em produção.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
