---
name: "validar-entrega"
title: "Validar a entrega integrada e sua prontidão"
category: "qualidade"
default_mode: "analisar"
origem: ["P32"]
related: ["coordenar-entregas", "mobile-e-responsividade", "acessibilidade", "estados-assincronos", "code-review", "migracoes-e-compatibilidade"]
description: "Use após uma ou mais frentes terminarem, para verificar o resultado combinado antes de encerramento, merge ou publicação. O modo padrão valida e relata; correções exigem que o modo seja explicitamente alterado."
---

# Validar a entrega integrada e sua prontidão

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar`). Uma instrução explícita da sessão prevalece.

## Quando usar

Após uma ou mais frentes terminarem, para verificar o resultado combinado antes de encerramento, merge ou publicação. O modo padrão valida e relata; correções exigem que o modo seja explicitamente alterado.

## Entradas úteis

- Entregas ou commits, critérios de aceite e ambiente disponível.
- Fluxos críticos, papéis de usuário e dispositivos relevantes.

## Instrução

Faça a validação integrada da entrega indicada. Avalie o produto que existe agora e os critérios de aceite acordados, sem confiar apenas no relato de cada frente. O modo padrão é analisar: execute verificações autorizadas e produza evidências, sem modificar o comportamento do produto. Se a sessão autorizar correções, faça apenas as necessárias para os problemas encontrados e valide novamente o que mudou.

### Delimite o que está sendo avaliado

Registre versão, branch ou conjunto de mudanças, ambiente, configuração relevante e dados de teste. Leia os critérios de aceite e o diff combinado. Identifique fronteiras alteradas: navegação, contratos, jobs, persistência, integrações, componentes compartilhados e instruções operacionais.

Verifique se as partes avaliadas estão realmente integradas. Dois PRs aprovados separadamente não demonstram que o resultado conjunto funciona. Separe falhas preexistentes de regressões, sem excluir problemas antigos que impeçam concluir o fluxo agora prometido.

Selecione cenários a partir do risco e da finalidade da entrega. Priorize tarefas completas do usuário e transições entre áreas. Não tente executar todos os testes imagináveis nem transformar a validação em uma refatoração geral.

### Percorra os fluxos de ponta a ponta

Exercite entrada, escolha de contexto, ação principal, persistência e retorno. Verifique o estado após recarregar ou reabrir a página. Inclua um caminho de erro recuperável e, quando relevante, estado vazio, permissão insuficiente, processamento assíncrono e resultado parcial.

Observe consistência de identidade, variante, versão, organização e ambiente durante todo o percurso. Confirme que uma seleção visual corresponde aos dados efetivamente usados pela operação. Verifique se uma ação pode ser repetida por duplo clique, retry, reconexão ou navegação e se essa repetição altera o resultado indevidamente.

Para UI, confira os tamanhos de tela relevantes e os estados de maior densidade. Use mobile, notebook e ultrawide quando o produto suportar esses contextos. Verifique foco, teclado, alvos de toque, legibilidade, feedback e preservação de contexto. Em fluxos mobile, diferencie emulação de viewport de teste do histórico e dos gestos em navegador ou dispositivo real.

Para mudanças operacionais, confira o ciclo entre aceite, fila, execução, conclusão e falha. Uma notificação de sucesso precisa corresponder a um efeito confirmado. Estado desconhecido ou conexão interrompida não deve aparecer como operação concluída.

### Verifique a preparação da entrega

Execute checks exigidos pelo repositório e verificações específicas das fronteiras alteradas. Avalie compatibilidade de migrations, configuração, artefatos e consumidores antigos quando necessário. Registre comandos, resultado e contexto suficiente para reproduzir falhas.

Não realize compras, pedidos físicos, mensagens externas ou deploys como parte implícita de um teste. Use ambientes e recursos autorizados. Se a validação final exigir uma ação real ainda não autorizada, prepare o cenário e informe o que falta observar, sem declarar esse caminho aprovado.

Compare a entrega com as promessas de seus relatos e documentos. Identifique funcionalidades anunciadas mas inacessíveis, estados tratados apenas no mock e instruções que não correspondem à implementação. Screenshots mostram composição visual; não substituem evidência de persistência ou de integração.

### Emita uma conclusão utilizável

Classifique o resultado como pronto no escopo verificado, pronto com limitações explicitadas ou bloqueado por problemas concretos. Para cada achado, indique impacto, reprodução, evidência e critério de correção. Evite uma aprovação absoluta quando houve restrição de ambiente.

Entregue a matriz compacta de cenários e resultados, evidências relevantes, falhas anteriores, regressões e pontos não verificados. Diga exatamente se a mudança foi apenas implementada, testada localmente, integrada, mergeada ou publicada. Conclua a validação quando os critérios acordados estiverem comprovados ou os bloqueios estiverem suficientemente caracterizados. Encaminhe correções necessárias ao fluxo apropriado, sem iniciar automaticamente novas melhorias fora do escopo.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
- Modelo de registro: [templates/resultado-e-validacao.md](../../templates/resultado-e-validacao.md)
