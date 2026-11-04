---
name: "simulacao-e-producao"
title: "Separar jogo, simulação e produção com regras coerentes"
category: "operacao"
default_mode: "analisar-e-corrigir"
origem: ["P34"]
related: ["versoes-e-rastreabilidade", "contratos-e-dados", "estados-assincronos", "elegibilidade-comercial", "metricas-e-custos", "seguranca-e-permissoes", "migracoes-e-compatibilidade"]
description: "Use quando ambientes de treinamento, jogo, laboratório ou demonstração compartilham código e interface com operações reais, ou para revisar execução de cenários, histórico e reinício de dados de teste sem perder o escopo da ação."
---

# Separar jogo, simulação e produção com regras coerentes

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando ambientes de treinamento, jogo, laboratório ou demonstração compartilham código e interface com operações reais. Também serve para revisar execução de cenários, histórico e reinício de dados de teste sem perder o escopo da ação.

## Entradas úteis

- Modos ou ambientes existentes e quais interfaces são compartilhadas.
- Operação representativa que deveria funcionar de forma coerente nos dois contextos.
- Fontes de dados de teste, efeitos externos e políticas de reinício já estabelecidas.

## Instrução

Analise e refine a relação entre os modos de jogo, simulação, laboratório e produção que existirem neste projeto. Quero que o ambiente de aprendizado represente regras úteis do mundo real e que cada operação tenha escopo e efeitos claros. Não crie novos modos apenas para seguir esta skill. Trabalhe no modo de execução autorizado na sessão.

### 1. Identifique o que muda entre os ambientes

Mapeie seleção de modo, origem dos registros, contas, credenciais, provedores e caminhos de execução. Quando a interface for compartilhada, determine como o contexto chega ao backend e acompanha consultas, comandos, jobs e resultados. Um rótulo visual não basta para demonstrar que os efeitos estão isolados.

Separe regras de domínio, dados de cenário e efeitos externos. Identifique diferenças intencionais de treinamento e divergências acidentais que ensinam um comportamento impossível em produção. Simulação pode simplificar tempo, disponibilidade ou resposta externa, mas precisa informar onde isso acontece. Não apresente um resultado simulado como confirmação de um fornecedor ou serviço real.

### 2. Propague o contexto corretamente

Verifique escopo por ambiente, usuário, conta, país, mundo, execução ou outra dimensão realmente existente. Siga esse contexto até banco, cache, filas, callbacks, arquivos e observabilidade. Uma seleção local na interface não pode alterar silenciosamente o contexto global de outras pessoas ou de processos já iniciados.

Revise a identidade das operações e resultados para impedir mistura entre execuções. Trate respostas atrasadas após uma troca de contexto e preserve a origem dos dados históricos. Se eventos externos chegam sem contexto suficiente, defina uma resolução confiável ou rejeite o caso ambíguo de forma explícita; não escolha um ambiente por conveniência.

### 3. Preserve coerência sem duplicar o domínio

Procure regras copiadas que já divergem entre modos, especialmente elegibilidade de produto, transições, permissões e limites. Compartilhe o que tem o mesmo significado e isole as diferenças que representam uma política consciente. Não imponha heranças, adapters ou camadas específicas antes de entender a arquitetura; escolha a separação com menor custo de manutenção para o caso real.

Resultados simulados devem ser rastreáveis a entradas, versão de regras e condições do cenário quando isso for necessário para reproduzi-los. Distingua dado real importado, dado sintético e resultado inferido. Evite inventar dados aparentemente oficiais apenas para preencher a interface. Quando a simulação utiliza recursos externos pagos, isso continua sendo um efeito real e deve respeitar a autorização existente.

### 4. Torne execução e reinício compreensíveis

Organize seleção, preparação, início, acompanhamento e consulta do resultado. Mantenha os controles relevantes acessíveis mesmo com listas e históricos extensos. Explicite se a ação atinge apenas o item selecionado, um país, um conjunto de cenários ou todo o ambiente. Navegar ou trocar uma seleção não deve executar, cancelar ou reiniciar processos por acidente.

Revise reinício, limpeza e repetição. Identifique registros dependentes, efeitos em andamento e histórico que precisa ser preservado. Prefira operações delimitadas e recuperáveis quando viáveis. Não apague dados, altere produção ou dispare pedidos, publicações e mensagens externas sem a autorização concreta exigida para a ação. Uma confirmação visual não substitui o controle de escopo no servidor.

### 5. Demonstre isolamento e fidelidade

Valide uma regra compartilhada em contextos controlados e exercite a troca de modo durante um fluxo quando esse risco existir. Verifique que jobs e resultados permanecem no contexto original, que caches não misturam dados e que repetir um cenário produz uma interpretação explicável. Teste os limites de reinício com dados descartáveis e autorizações compatíveis.

Entregue o mapa de contextos e efeitos, diferenças intencionais, defeitos confirmados, mudanças e evidências. Mostre quais elementos da simulação representam contratos reais e quais são simplificações declaradas. Conclua quando o usuário entende onde está operando e os caminhos revisados preservam contexto, rastreabilidade e limites de efeito. Registre separadamente as integrações ou cenários que não puderam ser exercitados.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
