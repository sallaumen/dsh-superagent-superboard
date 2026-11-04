---
name: "estados-assincronos"
title: "Corrigir estados assíncronos e atualizações em tempo real"
category: "operacao"
default_mode: "analisar-e-corrigir"
origem: ["P18"]
related: ["contratos-e-dados", "interacoes-diretas", "performance", "orquestracao-ias", "alertas-operacionais"]
description: "Use quando a interface parece parada, apresenta sucesso prematuro, perde progresso, mistura seleções ou fica inconsistente após recarregar e reconectar. Trata a consistência entre comando, processamento e apresentação; custo de execução é performance."
---

# Corrigir estados assíncronos e atualizações em tempo real

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando a interface parece parada, apresenta sucesso prematuro, perde progresso, mistura seleções ou fica inconsistente após recarregar e reconectar. Use esta skill para a consistência entre comando, processamento e apresentação; use `performance` quando o problema principal for custo de execução.

## Entradas úteis

- Operação assíncrona e tela afetadas; se não informadas, acompanhe a principal operação do escopo.
- Fontes de estado existentes: banco, jobs, eventos, callbacks ou serviços externos.
- Casos conhecidos de duplicidade, perda de feedback ou resposta fora de ordem.

## Instrução

Revise e corrija a comunicação entre ações do usuário, processamento assíncrono e atualização da interface. O usuário precisa saber o que foi solicitado, o que está acontecendo e qual resultado está confirmado. Investigue a implementação existente antes de escolher tecnologias ou redesenhar contratos. Trabalhe dentro do modo e do escopo definidos na sessão.

### 1. Reconstrua o ciclo real da operação

Siga uma ação desde o clique até o efeito persistido e a apresentação do resultado. Identifique quem aceita o comando, agenda o trabalho, executa, registra o resultado e notifica a interface. Determine qual fonte tem autoridade sobre cada estado e quais mensagens são apenas notificações. Desenhe uma máquina de estados pequena quando isso esclarecer transições que hoje estão implícitas.

Diferencie solicitação aceita, trabalho aguardando, execução iniciada, resultado confirmado, falha, cancelamento e estado desconhecido, usando apenas os estados que existem ou fazem sentido no domínio. Enfileirar um trabalho não prova que ele terminou. Uma conexão ativa não prova que os dados exibidos estão atualizados. Falha ao receber a resposta não prova que o efeito externo deixou de acontecer.

### 2. Procure condições de corrida e duplicação

Examine cliques repetidos, retries, callbacks duplicados, eventos fora de ordem e concorrência entre alterações. Verifique se a seleção atual está vinculada ao identificador correto: item, variante, versão, ambiente e operação. Uma resposta antiga não pode sobrescrever a escolha mais recente nem atribuir o resultado a outro registro.

Defina proteção proporcional: identidade da operação, controle de versão, deduplicação, transições condicionais ou outra estratégia compatível com a arquitetura. Use garantias verificáveis. Se um serviço externo não oferece meios de confirmar um efeito, represente essa incerteza e proponha reconciliação, em vez de prometer execução única absoluta. Cancelar a espera no navegador não significa cancelar o trabalho no servidor.

### 3. Faça reconexão e retorno funcionarem

Revise o comportamento ao recarregar, voltar à tela, suspender a aba, perder a conexão e reconectar. Decida como recuperar um retrato atual do estado e como complementar esse retrato com eventos. Evite depender exclusivamente de mensagens que podem ter sido perdidas. Reconcile atualizações em andamento sem reproduzir efeitos de negócio ou animar novamente um histórico inteiro como se estivesse acontecendo agora.

Indique atualização pendente ou dados potencialmente desatualizados quando necessário. Preserve filtros, seleção e foco sempre que ainda forem válidos. Confirme que assinaturas, timers e listeners antigos são removidos e que não surgem múltiplos consumidores após navegação repetida. O mecanismo de recuperação deve ser compreensível e observável para quem mantém o sistema.

### 4. Torne o feedback útil

Apresente confirmação de recebimento, processamento e resultado no contexto da ação. Desabilite ou altere controles apenas quando a operação realmente impedir nova interação. Distinga progresso conhecido de atividade indeterminada; não fabrique porcentagens. Para operações longas, permita continuar navegando e reencontrar o andamento quando isso fizer sentido.

Use atualização otimista somente quando houver uma estratégia coerente de confirmação, rejeição e reversão. Erros devem preservar dados úteis e oferecer uma próxima ação específica. Não faça o usuário depender de uma notificação temporária para descobrir uma falha importante. Garanta feedback acessível sem anunciar cada evento repetitivo ao leitor de tela e sem provocar mudanças bruscas de foco.

### 5. Valide as transições críticas

Reproduza o fluxo bem-sucedido e os riscos efetivamente encontrados: atraso, resposta antiga, duplicação, falha, recarregamento ou reconexão. Escolha testes que protejam a transição ou a invariável corrigida, além da verificação na aplicação em execução. Não multiplique testes de detalhes internos sem risco correspondente.

Entregue o mapa de estados e suas fontes, os problemas comprovados, os contratos ajustados e as evidências dos cenários validados. Declare qualquer transição que não pôde ser exercitada e o motivo. Considere concluído quando a interface converge para o estado real, conserva o contexto correto e permite recuperar falhas sem duplicar efeitos. Ampliações de arquitetura sem necessidade demonstrada devem permanecer fora desta entrega.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
