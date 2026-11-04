---
name: "versoes-e-rastreabilidade"
title: "Versões, seleção, publicação e rastreabilidade"
category: "arquitetura"
default_mode: "analisar-e-corrigir"
origem: ["P07"]
related: ["contratos-e-dados", "estados-assincronos", "assets-e-imagens", "migracoes-e-compatibilidade"]
description: "Use quando diferentes revisões de conteúdo, arte, configuração ou produto se confundem, resultados apontam para a versão errada ou visualizar algo altera indevidamente sua seleção principal. Trata identidade e ciclo de versões, não versionamento de dependências."
---

# Versões, seleção, publicação e rastreabilidade

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando diferentes revisões de conteúdo, arte, configuração ou produto se confundem, resultados apontam para a versão errada ou visualizar algo altera indevidamente sua seleção principal. Esta skill trata identidade e ciclo de versões, não versionamento de dependências.

## Entradas úteis

- Entidade versionada e operações envolvidas, como editar, aprovar, selecionar, publicar ou produzir.
- Relato ou exemplo de resultado associado à versão errada.
- Regras já existentes para histórico e compatibilidade.

## Instrução

Revise a gestão de versões e a rastreabilidade no escopo informado. Quero que cada conteúdo, resultado e ação relevante tenha identidade clara, e que o usuário consiga compreender qual versão está vendo e qual será efetivamente usada.

### Descubra as identidades e operações existentes

Mapeie a entidade lógica, suas revisões, seus arquivos, seus estados e os resultados que dependem dela. Identifique como as versões são criadas, selecionadas, aprovadas, publicadas, substituídas ou arquivadas. Acompanhe referências desde a interface até tarefas assíncronas, integrações e registros históricos.

Separe explicitamente versão mais recente, versão visualizada, versão escolhida como principal, versão aprovada e versão publicada, quando esses conceitos existirem. Não crie todos esses estados por padrão, mas não comprima significados diferentes em um único campo ambíguo.

Verifique se abrir uma revisão muda uma preferência persistida, se editar altera conteúdo que já foi referenciado e se a execução usa a versão selecionada ou consulta novamente a mais recente. Uma versão principal pode ser mais antiga e continuar correta.

### Encontre os pontos de perda de contexto

Inspecione URLs, formulários, cache, consultas, eventos, arquivos e payloads de tarefas. Procure referências implícitas a “atual”, nomes de arquivo reutilizados, associação por posição e resultados sem identificação de origem. Diferencie o identificador estável da entidade dos identificadores das suas revisões.

Investigue concorrência: duas edições, uma seleção alterada durante um processamento e respostas que chegam fora de ordem. Determine em que momento cada ação fixa a versão de entrada e como reconhece que o contexto mudou. Um resultado antigo não deve sobrescrever silenciosamente a revisão que o usuário acabou de escolher.

Examine o histórico com dados reais disponíveis. Procure registros que perderam origem ou misturam conteúdo de revisões distintas. Marque associações desconhecidas como desconhecidas; não deduza certeza a partir de datas próximas ou nomes parecidos.

### Defina invariantes úteis

Documente o conjunto mínimo de regras necessário. Exemplos: visualizar não publica; um resultado concluído continua ligado à entrada usada; uma ação confirma a revisão que terá efeito; referências históricas permanecem consultáveis mesmo após mudança da seleção principal.

Escolha entre revisão imutável, cópia de trabalho, snapshot ou outra representação conforme as necessidades existentes. Não introduza um sistema genérico de versionamento para toda entidade sem demonstrar benefício. Explique como corrigir um erro histórico e como desfazer uma seleção sem reescrever silenciosamente o passado.

Avalie o que deve ser transacional e o que pode convergir depois. Identifique permissões, regras de aprovação e conflitos que exigem resposta explícita. Evite decisões automáticas de “última gravação vence” quando isso puder publicar ou produzir conteúdo diferente do esperado.

### Corrija os caminhos de maior risco

No modo de correção, implemente um recorte completo de contratos, persistência e apresentação. Propague a identidade necessária por consultas, ações e tarefas. Atualize invalidação de cache e tratamento de respostas atrasadas quando afetados.

Na interface, mostre a versão relevante no momento da decisão e torne claras as consequências de selecionar, editar ou publicar. Evite acrescentar rótulos técnicos em toda superfície; concentre informação suficiente nos pontos em que ela evita erro ou ajuda a recuperar o contexto.

Planeje compatibilidade dos dados e consumidores anteriores. Não invente proveniência para registros legados. Preserve a consulta histórica e registre qualquer migração ou preenchimento que exija evidência adicional.

### Valide e entregue

Exercite pelo menos os cenários pertinentes ao recorte: visualizar uma revisão antiga, manter uma principal diferente da mais recente, mudar seleção com tarefa em andamento e consultar um resultado após novas revisões. Inclua erro, conflito e recuperação quando existirem.

Entregue o mapa de identidades, as invariantes, os defeitos encontrados, as mudanças realizadas e a evidência de que os resultados continuam ligados às entradas corretas. Separe dados corrigidos, dados apenas identificados e limitações históricas.

Conclua quando os fluxos escolhidos preservarem contexto e linhagem de forma verificável, sem efeitos implícitos de navegação ou ambiguidade sobre qual versão será usada.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
