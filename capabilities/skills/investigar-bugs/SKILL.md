---
name: "investigar-bugs"
title: "Investigação de bugs e correção da causa raiz"
category: "qualidade"
default_mode: "analisar-e-corrigir"
origem: ["P28"]
related: ["performance", "estados-assincronos", "estrategia-de-testes", "code-review"]
description: "Use quando existe um comportamento incorreto ou intermitente cuja causa ainda não foi demonstrada. Reproduz, testa hipóteses e corrige a causa; problema centrado em fluidez e frame rate é performance; estados distribuídos e reconexão, estados-assincronos."
---

# Investigação de bugs e correção da causa raiz

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando existe um comportamento incorreto ou intermitente cuja causa ainda não foi demonstrada. Para um problema centrado em fluidez e frame rate, use performance; para estados distribuídos e reconexão, estados-assincronos aprofunda os mecanismos específicos.

## Entradas úteis

- Sintoma, resultado esperado e passos conhecidos para reproduzir.
- Logs, horários, IDs de correlação ou gravações disponíveis, sem segredos.
- Ambiente afetado e alterações recentes que possam ajudar a formular hipóteses.

## Instrução

Investigue o problema informado, demonstre sua causa na medida possível e implemente uma correção delimitada. Quero que a solução explique o comportamento observado e preserve o funcionamento legítimo do sistema. Trate suspeitas iniciais como hipóteses, inclusive quando parecerem intuitivas.

### Descreva o problema de maneira verificável

Registre o resultado esperado, o observado, as condições de ocorrência e o impacto. Identifique ambiente, versão, dados relevantes, sequência de ações e frequência. Separe o que foi relatado pelo usuário do que você conseguiu observar diretamente.

Tente reproduzir o menor fluxo que preserva o sintoma. Compare uma situação afetada e uma equivalente que funciona quando isso ajudar. Não simplifique a reprodução a ponto de remover a condição que causa o defeito.

Examine mudanças recentes, logs, traces, eventos e estado persistido relacionados. Use identificadores de correlação quando existirem. Coincidência temporal com deploy, configuração ou ação do usuário não demonstra causalidade por si só.

### Construa e discrimine hipóteses

Formule um conjunto pequeno de causas plausíveis apoiadas em evidência. Para cada uma, registre qual observação seria esperada se estivesse correta e qual experimento ajudaria a distingui-la das demais.

Priorize experimentos baratos, reversíveis e informativos. Leia o caminho de execução e as fronteiras envolvidas antes de alterar parâmetros ou acrescentar mecanismos de retry. Evite tentar várias correções ao mesmo tempo, pois isso dificulta saber qual mudança resolveu o problema.

Considere estado antigo, entradas inesperadas, configuração, ordem de eventos, concorrência, cache, permissão, falha externa e diferença entre ambientes conforme o sintoma justificar. Não aplique uma lista universal de causas sem relação com os dados encontrados.

Quando não houver reprodução local, planeje observabilidade direcionada no ambiente autorizado. Colete apenas o necessário, proteja informações sensíveis e evite efeitos reais usados como experimento. Diga claramente o que a instrumentação permitirá concluir e o que continuará incerto.

### Explique o mecanismo da falha

Procure o primeiro ponto em que uma expectativa válida deixa de ser atendida, e não apenas o lugar em que a exceção aparece. Diferencie causa, condição disparadora e consequências posteriores. Um erro exibido na interface pode ter origem em um contrato, dado ou evento anterior.

Confirme se o defeito é novo, antigo ou exposto por uma mudança legítima. Consulte o histórico quando isso resolver a dúvida. Não atribua responsabilidade a um componente só porque seu nome aparece no log.

Descreva uma cadeia curta de causa e efeito com referências ao código e evidências observadas. Se ainda houver duas explicações viáveis, mantenha a incerteza explícita e faça o próximo teste que realmente possa separá-las.

### Corrija o mecanismo com escopo controlado

No modo de correção, implemente a menor mudança coerente que resolve a causa e mantém as invariantes do fluxo. Às vezes isso exige ajustar um contrato ou estado, e não apenas uma linha. Explique qualquer refatoração necessária para a correção.

Não esconda o sintoma convertendo falha em sucesso, ignorando exceções, desativando validação ou repetindo indefinidamente operações. Quando uma mitigação temporária for necessária, diferencie-a da correção definitiva, registre seu limite e defina a condição de retirada.

Preserve trabalho alheio e evite mudanças incidentais. Efeitos externos ou alterações destrutivas seguem a autorização concreta da sessão. Quando o bloqueio for falta de acesso, entregue a reprodução, a evidência disponível e o passo específico ainda necessário.

### Valide a correção e encerre

Repita a reprodução original nas condições relevantes e verifique um caminho legítimo próximo que poderia sofrer regressão. Adicione um teste durável se o caso proteger um risco real; não crie uma verificação que apenas imite a nova implementação.

Examine recuperação, repetição ou reconexão quando fizerem parte do defeito. Remova instrumentação temporária que deixou de ser necessária e mantenha somente a observabilidade que ajude a detectar recorrência sem gerar ruído excessivo.

Entregue sintoma, causa demonstrada ou grau de incerteza, mudança feita, evidência antes e depois e limitações. Conclua quando o problema estiver corrigido no escopo verificado ou quando houver um impedimento concreto documentado. Não declare uma falha intermitente eliminada apenas porque ela não apareceu em uma execução curta.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
- Modelo de registro: [templates/registro-de-diagnostico.md](../../templates/registro-de-diagnostico.md)
