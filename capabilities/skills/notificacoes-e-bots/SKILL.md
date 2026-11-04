---
name: "notificacoes-e-bots"
title: "Investigar bots, notificações e excesso de mensagens"
category: "operacao"
default_mode: "analisar-e-corrigir"
origem: ["P20"]
related: ["estados-assincronos", "setup-integracoes", "metricas-e-custos", "investigar-bugs", "alertas-operacionais"]
description: "Use quando um bot falha, notificações se repetem, há suspeita de bloqueio pelo provedor ou não é possível entender se o serviço está conectado e entregando. Telegram é um exemplo aplicável; o ciclo do problema apresentado ao usuário pertence a alertas-operacionais."
---

# Investigar bots, notificações e excesso de mensagens

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando um bot falha, notificações se repetem, há suspeita de bloqueio pelo provedor ou não é possível entender se o serviço está conectado e entregando. Telegram é um exemplo aplicável; o procedimento deve se adaptar ao canal efetivamente encontrado.

## Entradas úteis

- Canal, bot ou integração afetada e período aproximado do incidente.
- Sintomas, erros ou contadores disponíveis, removendo segredos e dados pessoais desnecessários.
- Ambiente autorizado para diagnóstico; testes com destinatários reais exigem autorização já existente na sessão.

## Instrução

Investigue e corrija o fluxo de bots e notificações no escopo indicado. Há suspeitas de excesso de mensagens, falhas de conexão ou bloqueio, mas quero um diagnóstico baseado em evidências. Descubra a causa antes de alterar políticas globais. Se o trabalho estiver em modo de análise, preserve o sistema e entregue as correções propostas.

### 1. Reconstrua o caminho de entrada e de saída

Identifique os provedores, contas e ambientes reais. Mapeie recebimento por polling, webhook ou mecanismo equivalente; processamento, agendamento e envio; e confirmação ou falha observável. Verifique quais instâncias executam cada responsabilidade e como se comportam durante deploy, reinício e escalonamento.

Separe falha de recebimento, falha de autenticação, conflito entre consumidores, rejeição de envio, limitação temporária e bloqueio confirmado. Um contador de ocorrências de erro não prova que igual quantidade de mensagens foi enviada. Examine o código da resposta, o corpo relevante, o horário e o identificador da operação, com segredos removidos. Considere causas alternativas antes de concluir que o provedor baniu a conta.

### 2. Verifique contratos e limites atuais

Consulte a documentação oficial do provedor e a versão da biblioteca utilizada para interpretar o erro e a política aplicável. Não codifique números de limite recuperados de memória sem verificar seu escopo. Limites podem depender de destinatário, operação, conta ou condição do serviço; modele apenas as distinções confirmadas e necessárias.

Inspecione configuração duplicada, múltiplos pollers, endpoints ativos indevidos, tokens revogados e conflitos de ambiente quando forem hipóteses plausíveis. Não exponha credenciais em logs, relatórios ou telas. Verifique a configuração por meios seguros e informe apenas o estado que interessa à operação.

### 3. Corrija repetição e recuperação

Siga a identidade de uma notificação desde o evento de origem. Procure loops, jobs duplicados, retries sem limite, agendamento recorrente acidental e falhas que disparam novas notificações sobre a própria falha. Diferencie repetição legítima, agregação desejada e duplicata. Defina deduplicação com uma chave e uma janela justificadas pelo significado da mensagem.

Respeite sinais de espera oferecidos pelo provedor, quando existirem. Escolha políticas de retry, atraso e recuperação adequadas ao tipo de falha. Não repita indefinidamente erros permanentes. Uma resposta perdida pode deixar o envio incerto; trate essa condição conforme os recursos de reconciliação disponíveis, sem prometer entrega exatamente uma vez quando o contrato externo não oferece essa garantia.

### 4. Torne a operação compreensível

Apresente o estado da integração no painel operacional apropriado: configuração, recebimento, processamento e envio podem ter situações diferentes. Mostre última atividade confirmada, falha atual, próxima tentativa conhecida e ação útil para recuperação. Evite um único indicador verde que esconda a degradação de uma etapa.

Agrupe incidentes equivalentes sem esconder frequência, duração ou impacto. Permita distinguir alerta reconhecido de problema resolvido. Para usuários finais, entregue mensagens relevantes e proporcionais ao evento; para operadores, mantenha detalhes suficientes para localizar a causa. Não transforme cada retry em uma notificação adicional para o mesmo destinatário.

### 5. Valide sem gerar novo incidente

Use testes locais, respostas controladas ou ambientes de teste para exercitar sucesso, rejeição, limitação, timeout, duplicação e recuperação conforme os riscos encontrados. Não envie mensagens a pessoas, faça disparos em massa ou altere configurações externas sem autorização concreta. Caso a sessão já autorize um teste real delimitado, execute somente esse teste e registre o resultado.

Entregue uma linha do tempo do incidente, causas confirmadas, hipóteses descartadas ou ainda abertas, mudanças e evidências. Informe o que os contadores realmente medem e quais estados agora ficam visíveis. Encerre quando o caminho defeituoso estiver corrigido e a recuperação for verificável. Se faltarem registros do provedor, descreva precisamente a evidência necessária, sem apresentar uma suposição como diagnóstico final.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
- Fontes e conceitos: [referencias/fontes-e-conceitos.md](../../referencias/fontes-e-conceitos.md)
