---
name: "assets-e-imagens"
title: "Refinar imagens, prévias e rastreabilidade de assets"
category: "operacao"
default_mode: "analisar-e-corrigir"
origem: ["P23"]
related: ["versoes-e-rastreabilidade", "identidade-ui", "mobile-e-responsividade", "estados-assincronos", "setup-integracoes", "elegibilidade-comercial"]
description: "Use quando produtos ou criações não têm imagens úteis, frente e verso estão confusos, a prévia não acompanha a seleção ou não se sabe de onde veio um asset. Aplica-se também a resultados de geração, composição e processamento de imagens."
---

# Refinar imagens, prévias e rastreabilidade de assets

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando produtos ou criações não têm imagens úteis, frente e verso estão confusos, a prévia não acompanha a seleção ou não se sabe de onde veio um asset. Aplica-se também a resultados de geração, composição e processamento de imagens.

## Entradas úteis

- Objeto e fluxo de criação, edição, catálogo ou amostras no escopo.
- Fontes de imagens existentes e serviços disponíveis para produzir prévias.
- Requisitos de fidelidade visual e ações externas já autorizadas.

## Instrução

Revise e refine a experiência visual e o pipeline de imagens deste escopo. O usuário deve reconhecer o item que está criando ou escolhendo, verificar suas características e confiar na relação entre a prévia e a seleção atual. Investigue as fontes e a implementação antes de acrescentar geração de imagens ou novas dependências. Aplique correções conforme o modo autorizado para a tarefa.

### 1. Descubra o que cada imagem representa

Inventarie os assets utilizados e sua origem: fotografia, imagem de catálogo, mockup do fornecedor, composição local, renderização ou ilustração gerada por IA. Identifique item, variante, cor, arte, versão, vista e contexto associados. Diferencie a imagem disponível da que a interface deveria solicitar para representar a escolha atual.

Verifique frente, verso, detalhes e outras vistas somente quando existirem ou puderem ser produzidas por um processo adequado. Não apresente uma vista inventada como fotografia ou evidência do fornecedor. Um preview visualmente convincente não confirma capacidade de produção, posição exata de impressão, cor física ou disponibilidade comercial. Quando houver aproximações, comunique a limitação de forma curta e contextual.

### 2. Organize a experiência de inspeção

Escolha a imagem principal e as vistas secundárias de acordo com a decisão do usuário. Permita comparar, ampliar ou alternar detalhes quando isso ajudar a avaliar o produto. A seleção deve ser perceptível e acompanhar as informações relevantes, sem ocupar a tela com grandes blocos de texto ou placeholders vazios.

Trate ausência, carregamento, processamento e falha como estados distintos. Use proporções, enquadramento e fundos coerentes, sem distorcer o item. Considere telas pequenas e grandes, contraste, navegação por teclado e descrições acessíveis que identifiquem o conteúdo útil. O espaço reservado deve evitar saltos desnecessários na composição, mas não criar áreas desproporcionais quando não há mídia disponível.

### 3. Corrija identidade e ciclo de vida

Mapeie a geração, o armazenamento, a transformação e a entrega dos assets. Defina uma identidade suficiente para impedir colisões entre produtos, variantes e versões de arte. Revise invalidação de cache e atualização da prévia após edição. Uma resposta atrasada não pode substituir a imagem de uma seleção mais recente.

Examine jobs de geração, deduplicação, retries e processamento parcial. Distinga preview pendente de preview definitivo e preserve a relação com a operação que o criou. Limpe apenas assets comprovadamente descartáveis dentro de uma política segura; não remova arquivos ainda referenciados por histórico, pedidos ou versões publicadas. Não exponha credenciais ou URLs privadas desnecessárias na interface e nos registros de diagnóstico.

### 4. Use IA onde a contribuição for verificável

Avalie se IA resolve uma lacuna real: interpretação de requisitos, assistência de composição ou prévia ilustrativa, por exemplo. Compare com recursos já disponíveis no fornecedor e com composição determinística. Se o uso se justificar, mantenha a integração em uma camada clara, com identidade da entrada, resultado, falha, custo conhecido ou estimado e possibilidade de repetir conscientemente.

Não use geração para inventar características do produto nem para substituir evidência de compatibilidade. Preserve a distinção entre a versão da criação e a versão do asset derivado. Uma nova imagem não deve mudar silenciosamente a arte aprovada, o produto selecionado ou a oferta publicada. Chamadas que geram custo externo seguem a autorização e os limites definidos na sessão.

### 5. Valide o que o usuário efetivamente vê

Exercite um fluxo completo, incluindo seleção de outra variante ou versão durante um carregamento, quando esse risco existir. Confira também ausência de uma vista, falha de geração, retorno à tela e reuso de cache. Use assets controlados e compare a prévia com os identificadores realmente associados, além de verificar sua aparência.

Entregue o mapa de fontes e transformações, as regras de associação e invalidação, as melhorias de apresentação e evidências do fluxo funcionando. Declare quais imagens são representativas e quais dependem de informação externa não verificada. Conclua quando o usuário consegue inspecionar a seleção correta, compreender limitações relevantes e recuperar falhas sem confundir versões ou origens. Ideias de direção artística que não resolvam o escopo ficam separadas da entrega.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
