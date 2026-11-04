---
name: "estrategia-de-testes"
title: "Estratégia de testes orientada a riscos e lacunas reais"
category: "qualidade"
default_mode: "analisar-e-corrigir"
origem: ["P26"]
related: ["testes-redundantes", "code-review", "investigar-bugs", "validar-entrega"]
description: "Use quando a suíte passa, mas defeitos importantes escapam, ou quando falta clareza sobre quais comportamentos merecem proteção. Escolhe testes pelo risco e pelas fronteiras; para remover duplicações já identificadas, use testes-redundantes."
---

# Estratégia de testes orientada a riscos e lacunas reais

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando a suíte passa, mas defeitos importantes escapam, ou quando falta clareza sobre quais comportamentos merecem proteção. Para remover duplicações já identificadas, use testes-redundantes.

## Entradas úteis

- Fluxo, mudança ou risco prioritário.
- Histórico de incidentes, quando disponível.
- Limites de execução e ambientes de teste existentes.

## Instrução

Revise a estratégia de testes do escopo informado e corrija as lacunas de maior consequência. Quero evidência de que os comportamentos importantes estão protegidos, com uma suíte sustentável. Não aumente testes ou cobertura percentual como objetivo isolado.

### Entenda o risco antes de escolher a técnica

Identifique os usuários, contratos e efeitos do fluxo. Liste o que pode falhar e qual seria a consequência: decisão errada, perda de dados, acesso indevido, cobrança repetida, resultado associado à entidade errada, interface bloqueada ou incapacidade de recuperar uma operação.

Consulte o comportamento implementado, requisitos atuais, incidentes e testes existentes. Separe regras reais de expectativas antigas. Não use a implementação como única fonte da resposta correta, pois isso pode apenas reproduzir o mesmo defeito no teste.

Defina um oráculo verificável para cada risco: uma regra do domínio, um contrato documentado, uma invariável, um exemplo aprovado ou uma observação reproduzível. Quando a regra estiver ambígua, esclareça o significado antes de cristalizar uma suposição na suíte.

### Mapeie proteção e lacunas

Relacione os riscos prioritários com os testes que de fato os exercitam. Examine dados, asserções e fronteiras atravessadas. Um teste com o nome certo pode não verificar persistência, autorização ou recuperação que seu título sugere.

Identifique lacunas relevantes em caminhos de sucesso, entradas inválidas, estados vazios, falhas externas, repetição, concorrência, isolamento, transições de estado e compatibilidade. Escolha os casos aplicáveis ao domínio; não crie automaticamente todas essas categorias em todos os módulos.

Avalie o equilíbrio entre testes rápidos de regras, contratos de fronteira e poucos fluxos integrados representativos. A distribuição adequada depende da arquitetura e do risco. Evite impor uma pirâmide numérica ou levar toda a cobertura para testes de ponta a ponta.

### Desenhe verificações que detectem defeitos

Prefira asserções sobre resultados e efeitos observáveis. Use doubles para controlar dependências quando necessário, mantendo verificações reais das fronteiras que constituem o risco. Não faça a suíte passar simulando a própria garantia que deveria provar.

Escolha fixtures mínimas, legíveis e representativas. Evite dados tão artificiais que ignorem relações importantes, e não copie informações sensíveis de produção. Defina tempo, aleatoriedade e ordem de execução de maneira controlável quando influenciarem o cenário.

Considere testes baseados em propriedades para invariantes com muitas combinações, contratos para integrações estáveis e verificações visuais para regressões de composição, quando forem adequados. Cada técnica precisa ter um motivo concreto. Snapshots extensos e atualizados sem inspeção não substituem uma expectativa de comportamento.

### Implemente o conjunto prioritário

No modo de correção, adicione ou ajuste os casos que fecham as lacunas mais importantes. Faça o teste expressar o defeito ou regra antes de alterar a implementação quando isso ajudar a demonstrar a correção. Se a investigação revelar um bug, corrija-o em um lote compreensível e registre a relação com o teste.

Verifique isolamento entre execuções, preparação e limpeza de recursos, dependência de rede e comportamento sob paralelismo. Não execute operações externas pagas ou destrutivas apenas para obter cobertura. Use os ambientes e autorizações disponíveis e declare o que eles conseguem demonstrar.

Corrija causas de intermitência que afetam os cenários escolhidos. Retries e esperas fixas podem ocultar problemas de sincronização; prefira condições observáveis e limites proporcionais. Não amplie a suíte para compensar uma regra de produto que ainda não foi definida.

### Entregue um mapa verificável

Mostre uma matriz curta de risco, comportamento esperado, verificação existente, lacuna tratada e evidência. Inclua os comandos executados, o ambiente e limitações relevantes, sem transformar o relatório em transcrição integral de logs.

Explique o que passou a ser detectado e por que os novos testes devem continuar válidos após refatorações internas legítimas. Registre riscos que ainda dependem de ambiente, acesso ou decisão de produto.

Conclua quando o conjunto prioritário estiver protegido e estável nas condições verificadas. Pare de adicionar casos quando o risco remanescente estiver explicitado; cobertura total teórica e ausência de bugs não são promessas que uma rodada de testes pode fazer.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
