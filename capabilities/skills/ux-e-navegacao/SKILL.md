---
name: "ux-e-navegacao"
title: "Revisar a experiência completa e a navegação entre páginas"
category: "interface"
default_mode: "analisar-e-corrigir"
origem: ["P11"]
related: ["coordenar-entregas", "identidade-ui", "mobile-e-responsividade", "estados-assincronos", "validar-entrega"]
description: "Use quando o usuário encontra caminhos confusos, retornos desnecessários, perda de contexto ou dificuldade para concluir tarefas. A unidade de análise é o fluxo completo, mesmo que atravesse páginas ou áreas diferentes."
---

# Revisar a experiência completa e a navegação entre páginas

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando o usuário encontra caminhos confusos, retornos desnecessários, perda de contexto ou dificuldade para concluir tarefas. A unidade de análise é o fluxo completo, mesmo que atravesse páginas ou áreas diferentes.

## Entradas úteis

- Tarefa principal, público e limites da frente.
- Fluxos problemáticos ou reclamações conhecidas.
- Rotas, dados de uso e referências de produto, quando existirem.

## Instrução

Analise e refine a experiência completa do escopo informado, da entrada até a conclusão das principais tarefas. Explore todas as páginas internas relevantes e como elas se conectam. Quero que o usuário entenda onde está, o que pode fazer, o que está acontecendo e qual é o próximo passo, com menos retrabalho e perda de contexto.

### Reconstrua a jornada real

Identifique as tarefas prioritárias e os diferentes pontos de entrada: navegação principal, busca, link compartilhado, notificação, atualização da página e retorno de uma sessão. Confira as jornadas na aplicação e associe problemas ao código e aos contratos que os produzem. Diferencie limitações confirmadas de hipóteses levantadas por uma imagem ou relato.

Mapeie as páginas e transições em um diagrama compacto. Marque decisões, pré-requisitos, estados terminais, retornos e pontos de perda de contexto. Não desenhe todos os componentes; o mapa deve revelar caminhos redundantes, páginas sem saída, ações ambíguas e etapas que poderiam estar próximas.

Para cada tarefa, identifique o que o usuário sabe ao entrar, qual resultado espera e qual informação precisa antes de agir. Observe se nomes e rótulos representam seu objetivo ou apenas a estrutura interna do software. Localize ações que parecem disponíveis, mas dependem de configurações ou dados ainda ausentes.

### Melhore a continuidade

Reduza desvios e ciclos que não acrescentam valor. Preserve retornos legítimos para comparar, revisar e corrigir escolhas. Um processo exploratório não precisa virar um assistente linear, e uma tarefa simples não deve ganhar etapas artificiais. Escolha a estrutura que torne as dependências compreensíveis com o menor esforço.

Mantenha o contexto necessário ao navegar: item, versão, filtros, seleção, ordenação e posição, conforme o caso. Diferencie o objeto sendo visualizado daquele selecionado para uma operação ou definido como padrão. Voltar para uma lista não deve silenciosamente alterar escolhas ou repetir efeitos de negócio.

Torne as consequências das ações claras. Ao concluir uma operação, mostre seu resultado e ofereça o próximo passo relevante. Se houver bloqueio, informe o motivo e um caminho de resolução que realmente exista. Evite botões que apenas redirecionam para páginas genéricas quando é possível abrir diretamente a configuração ou o item necessário.

### Complete os estados do fluxo

Avalie carregamento, vazio, conteúdo parcial, indisponibilidade, erro recuperável, sucesso e perda de conexão. Explique o que o sistema sabe e o que ainda precisa confirmar. Não apresente dados desconhecidos como zero nem trate uma solicitação aceita como trabalho concluído.

Revise formulários e escolhas repetidas. Reaproveite dados confiáveis já disponíveis, sugira opções válidas e exponha claramente quando uma inferência precisa de confirmação. Preserve edição e recuperação de erros. Evite automatismos silenciosos que mudem destino, versão, publicação, cobrança ou outra decisão material do usuário.

Identifique discrepâncias entre frontend e backend que impedem uma experiência coerente. No modo de correção, ajuste os contratos necessários dentro do escopo e valide o comportamento resultante. Se a decisão muda a finalidade do produto ou exige uma escolha real do usuário, apresente opções curtas com sua recomendação; continue o trabalho independente dessa decisão.

### Valide como uma pessoa usaria

Percorra os caminhos principais e alternativas relevantes com dados representativos. Teste entrada direta, recarregamento, voltar e avançar, mudança de seleção e retomada após erro. Observe a experiência em telas pequenas e amplas. Separe verificação no navegador, simulação e observação em dispositivo real.

Implemente em entregas coerentes, preservando outras frentes e evitando reconstruir áreas alheias apenas para obter uniformidade. Acrescente testes quando protegem uma regra de navegação ou estado que poderia regredir; não use snapshots de layout como substituto da avaliação do fluxo.

Entregue o mapa anterior e o resultante, as principais fricções removidas, mudanças realizadas e evidências das jornadas percorridas. Conclua quando as tarefas delimitadas tiverem entrada, progresso, recuperação e saída compreensíveis, com pendências concretas identificadas. Não apresente preferência estética como evidência de melhora de usabilidade.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
