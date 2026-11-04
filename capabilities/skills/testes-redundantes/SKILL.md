---
name: "testes-redundantes"
title: "Limpeza de testes duplicados e manutenção da cobertura útil"
category: "qualidade"
default_mode: "analisar-e-corrigir"
origem: ["P25"]
related: ["consolidar-codigo", "estrategia-de-testes", "code-review", "build-ci-dependencias"]
description: "Use quando a suíte repete cenários, dificulta mudanças ou ficou lenta por redundância. Remove redundância preservando a cobertura que detecta riscos distintos; lacunas e estratégia de qualidade pertencem a estrategia-de-testes."
---

# Limpeza de testes duplicados e manutenção da cobertura útil

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando a suíte repete cenários, dificulta mudanças ou ficou lenta por redundância. O objetivo é simplificar a proteção existente; uma revisão ampla das lacunas de qualidade pertence a estrategia-de-testes.

## Entradas úteis

- Conjunto de testes, área ou lentidão a investigar.
- Comandos e restrições da suíte, se conhecidos.
- Incidentes ou riscos que precisam continuar protegidos.

## Instrução

Revise os testes do escopo informado para eliminar redundância real, melhorar clareza e reduzir manutenção sem perder proteção relevante. Não use a quantidade de testes removidos ou a redução de linhas como medida de sucesso. Quero uma suíte que continue detectando os comportamentos errados que importam.

### Estabeleça a situação inicial

Identifique os comandos oficiais, a organização da suíte e as condições necessárias para executá-la. Registre falhas preexistentes, testes intermitentes e dependências de ambiente. Execute uma amostra ou o conjunto apropriado ao recorte antes de modificar, proporcionalmente ao custo e ao risco.

Mapeie o que os grupos de testes protegem: regra, contrato, integração, comportamento da interface, autorização ou regressão histórica. Leia asserções, fixtures e preparação; nomes parecidos não comprovam equivalência, e arquivos diferentes podem repetir exatamente o mesmo risco.

Quando duração motivar a tarefa, meça o custo nas mesmas condições de comparação. Considere inicialização, banco, rede, paralelismo e variação de máquina. Não atribua ganho à limpeza apenas porque uma execução isolada ficou mais rápida.

### Diferencie duplicação de proteção complementar

Compare comportamento observável, precondições, fronteira exercitada, forma de falha e camada de execução. Dois testes podem usar os mesmos dados e proteger riscos diferentes. Um teste unitário de cálculo e uma integração que verifica persistência não são duplicados apenas porque esperam o mesmo valor final.

Classifique candidatos como duplicação exata, variação útil, parametrização possível, cobertura complementar, teste acoplado à implementação, cenário obsoleto ou teste sem asserção significativa. Explique qual defeito cada teste detectaria que os demais não detectam.

Observe casos de autorização, isolamento entre contas, erros, limites, concorrência e regressões conhecidas. Não remova essas diferenças porque o caminho de sucesso já está coberto. Também não preserve testes sem valor apenas por terem sido criados antes.

### Escolha a simplificação adequada

Para cada remoção proposta, identifique o teste ou contrato que continuará protegendo o comportamento. Se não houver equivalente, a remoção precisa ser justificada pela retirada legítima do comportamento ou pela substituição por uma verificação melhor.

Parametrize cenários quando isso reduzir repetição e mantiver as diferenças legíveis. Preserve nomes e diagnósticos que permitam entender uma falha sem desmontar uma estrutura genérica complexa. Evite helpers com vários modos e flags que escondem o que cada caso prepara.

Reduza fixtures excessivas e mocks desnecessários quando isso melhorar o significado do teste. Não troque uma integração importante por mocks que apenas confirmam a sequência interna de chamadas. Testes de detalhes privados podem ser substituídos por contratos observáveis, sem obrigar uma refatoração ampla do produto.

### Faça mudanças em lotes compreensíveis

No modo de correção, remova, una ou reescreva apenas os candidatos com justificativa clara. Mantenha separadas mudanças no comportamento da aplicação e mudanças na suíte, salvo quando corrigir um defeito demonstrado exigir ambas.

Não resolva testes intermitentes apagando-os, aumentando tolerâncias indiscriminadamente ou adicionando retries que escondem falhas. Investigue sua causa ou registre uma quarentena justificada conforme a política existente, com responsável e condição de retorno quando esse mecanismo existir.

Preserve cenários de regressão cujo contexto não esteja óbvio. Consulte histórico disponível quando isso puder explicar sua finalidade. Ausência de uma boa descrição é motivo para melhorar a documentação do caso, não prova de inutilidade.

### Comprove que a proteção permaneceu

Execute o conjunto afetado e as fronteiras necessárias depois de cada lote. Compare o mapa de comportamentos antes e depois. Quando houver dúvida concreta sobre a utilidade de uma asserção, use uma alteração controlada e reversível ou teste de mutação direcionado para verificar que ela detecta a falha; não imponha essa técnica à suíte inteira.

Entregue os grupos analisados, as decisões por candidato, o destino da cobertura e os resultados das execuções. Diferencie tempo medido de estimativa e testes executados de testes apenas inspecionados.

Conclua quando o recorte estiver mais claro e com redundâncias justificadamente removidas, mantendo proteção identificável para os riscos relevantes. Registre lacunas descobertas para uma próxima rodada, sem transformar esta limpeza em expansão ilimitada da suíte.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
