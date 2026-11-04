---
name: "interacoes-diretas"
title: "Substituir controles excessivos por interações visuais diretas"
category: "interface"
default_mode: "analisar-e-corrigir"
origem: ["P14"]
related: ["identidade-ui", "acessibilidade", "estados-assincronos"]
description: "Use quando ações simples exigem grandes formulários, textos repetitivos ou etapas dispensáveis. Serve para avaliações, seleções, favoritos, filtros e ajustes que podem ganhar uma representação visual clara, sem esconder regras de negócio."
---

# Substituir controles excessivos por interações visuais diretas

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando ações simples exigem grandes formulários, textos repetitivos ou etapas dispensáveis. Serve para avaliações, seleções, favoritos, filtros, ajustes e outras ações que podem ganhar uma representação visual clara.

## Entradas úteis

- Interações a simplificar e regra de negócio correspondente.
- Tipos de entrada suportados: mouse, toque, teclado e tecnologias assistivas.
- Identidade visual e limites para salvamento automático, quando definidos.

## Instrução

Revise as interações do escopo informado e substitua controles desproporcionais por formas mais diretas, visuais e agradáveis de agir. Quero reduzir espaço e esforço sem tornar funções misteriosas, retirar informação necessária ou mudar silenciosamente regras de negócio. A solução deve comunicar o valor atual, a ação possível e seu resultado.

### Escolha oportunidades reais

Inventarie ações frequentes e identifique quais possuem um conjunto simples de escolhas, resultado facilmente representável e baixo custo de reversão. Observe formulários grandes para uma única decisão, confirmações redundantes, rótulos repetidos e estados que poderiam aparecer no próprio objeto.

Antes de redesenhar, confira o contrato de cada ação: escala, valores válidos, possibilidade de desfazer, autoria, permissões e momento de persistência. Diferencie ações locais e reversíveis de publicação, cobrança, exclusão ou operações externas com consequências. Uma interação compacta não torna essas consequências menores.

### Desenhe a interação completa

Use representações visuais adequadas ao significado: estrelas para avaliação quando fizer sentido, estados de seleção, controles segmentados, miniaturas, indicadores ou manipulação direta. Não transforme qualquer formulário em um conjunto de ícones. Mantenha rótulos curtos quando o significado não for evidente e disponibilize nomes acessíveis para controles visuais.

Por exemplo, em uma avaliação por estrelas, o hover pode antecipar o valor sob o ponteiro e o clique confirmar. Ao sair sem confirmar, restaure a representação persistida. No toque e no teclado, ofereça uma maneira equivalente e compreensível de escolher. Não salve apenas porque o ponteiro passou sobre uma estrela.

Preserve a escala real. Se os dados usam notas de zero a dez, decida como representá-las sem converter ou arredondar silenciosamente; considere o domínio antes de escolher estrelas inteiras ou frações. Diferencie ausência de voto, voto zero e avaliação de outra pessoa ou sistema. Não confunda prévia, escolha local e valor efetivamente salvo.

Para cada interação, defina estados inicial, foco, intenção, envio, sucesso e falha. A resposta visual deve ser discreta, mas perceptível. Indique quando existe trabalho em andamento sem bloquear toda a página. Evite mensagens de sucesso que desaparecem antes de serem percebidas ou notificações repetidas para cada pequeno movimento.

### Conecte a experiência ao estado real

Avalie salvamento automático apenas onde a ação e suas consequências forem claras. Se usar atualização otimista, mantenha o valor anterior e uma recuperação coerente quando o servidor rejeitar. Respostas fora de ordem não podem sobrescrever uma escolha mais recente. Trate cliques rápidos, repetição de envio, mudanças de contexto e reconexão conforme o contrato da operação.

Não crie sucesso artificial com animações ou temporizadores. Um estado pendente deve refletir o que o sistema realmente conhece. A conclusão visual precisa estar ligada ao resultado confirmado, e ações relevantes devem preservar rastreabilidade quando ela já fizer parte do domínio.

Garanta que a representação funcione com pouco movimento, alto contraste quando aplicável e sem depender apenas de cor. Mantenha foco visível e comportamento por teclado previsível. Não reduza a área interativa junto com o desenho se isso dificultar o toque. Detalhes importantes precisam estar acessíveis também sem hover.

### Implemente e verifique

No modo de correção, escolha um conjunto coerente de interações e desenvolva componentes reaproveitáveis onde houver semântica comum. Evite um componente universal com muitas combinações incompatíveis. Remova os controles antigos somente quando as capacidades e os estados necessários estiverem atendidos.

Valide mouse, toque e teclado, além de salvamento lento, falha, retorno à página e mudanças rápidas. Acrescente testes para transições e persistência que protejam o comportamento; não se limite a testar a presença de ícones. Observe se a simplificação reduz esforço sem aumentar dúvidas.

Entregue as interações transformadas, suas regras, evidências de funcionamento e limitações. Conclua quando os usuários puderem descobrir, executar e compreender o resultado das ações delimitadas, com recuperação de falhas e significado dos dados preservado.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
