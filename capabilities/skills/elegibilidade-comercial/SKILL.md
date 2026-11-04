---
name: "elegibilidade-comercial"
title: "Validar catálogo e elegibilidade comercial"
category: "operacao"
default_mode: "analisar-e-corrigir"
origem: ["P22"]
related: ["versoes-e-rastreabilidade", "contratos-e-dados", "setup-integracoes", "assets-e-imagens", "migracoes-e-compatibilidade", "simulacao-e-producao"]
description: "Use quando um sistema oferece produtos em mercados, lojas ou canais sem comprovar a capacidade de produção ou atendimento. Valida a combinação exata (variante, fornecedor, destino) com fonte e data, preservando desconhecido e bloqueios."
---

# Validar catálogo e elegibilidade comercial

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando um sistema oferece produtos em mercados, lojas ou canais sem comprovar a capacidade de produção ou atendimento. O foco é a regra de elegibilidade e sua rastreabilidade, deixando uma base confiável para o posterior refinamento visual.

## Entradas úteis

- Mercado, produto, loja ou fornecedor prioritário; sem preferência, escolha um fluxo representativo do escopo.
- Significado desejado de país e atendimento, caso já esteja definido no negócio.
- Ambientes, fontes de catálogo e ações comerciais autorizadas.

## Instrução

Analise e corrija a arquitetura que conecta produtos, fornecedores, mercados, lojas e canais neste escopo. Quero que a oferta comercial tenha uma justificativa verificável de atendimento. Descubra os contratos existentes e implemente as correções permitidas pelo modo da tarefa, preservando registros históricos e evitando alterações externas não autorizadas.

### 1. Mapeie entidades e significados

Siga um produto desde sua criação até a oferta em uma loja. Identifique produto base, variante, arte ou personalização, SKU do fornecedor, método de produção, áreas de impressão, conta, marca, loja, canal e mercado, conforme existirem. Não suponha que esses conceitos estejam bem separados nem introduza entidades sem necessidade demonstrada.

Esclareça o uso de país: país de cadastro do fornecedor, origem de produção, origem de envio e destino de entrega podem representar coisas diferentes. Determine qual condição o negócio exige. Se houver uma decisão de produto realmente aberta, apresente opções simples e a consequência de cada uma; não escolha silenciosamente um significado que possa alterar o que será vendido.

### 2. Verifique a elegibilidade exata

Procure evidência de que a combinação ofertada pode ser produzida e atendida. Disponibilidade de uma camiseta preta não demonstra disponibilidade da rosa; uma técnica ou área de impressão suportada não prova outra. Considere os atributos relevantes, como tamanho, cor, material, personalização, quantidade e destino, sem criar uma matriz maior do que o domínio exige.

Defina a fonte, a data e o escopo de cada confirmação. Diferencie combinação confirmada, bloqueada por uma regra conhecida, pendente de verificação e informação desatualizada. Não transforme ausência de dado em disponibilidade. Quando existir fallback entre fornecedores, verifique se ele preserva as características prometidas, em vez de trocar silenciosamente por um produto diferente.

### 3. Defina uma regra central e consumível

Localize validações espalhadas e contratos que divergem entre cadastro, catálogo, publicação e compra. Proponha uma forma consistente de avaliar elegibilidade e devolver razões estruturadas, considerando as particularidades dos provedores. A interface deve conseguir explicar o bloqueio e oferecer a próxima ação sem reproduzir toda a regra de negócio.

Decida em quais pontos revalidar: edição da variante, sincronização do fornecedor, mudança de destino, publicação e operação posterior. Avalie a janela entre checagem e uso e quais garantias o serviço externo realmente oferece. Elegibilidade comercial não deve ser apresentada como reserva de estoque ou entrega garantida quando esses compromissos não existem no contrato.

### 4. Preserve escala, isolamento e história

Verifique o isolamento entre contas, marcas, lojas, canais e ambientes. Uma associação válida em uma loja ou credencial não pode vazar para outra. Identifique consultas ou sincronizações que crescem mal com o número de lojas e variantes, corrigindo os gargalos demonstrados no caminho escolhido, sem redesenhar todo o sistema por uma escala hipotética.

Quando o catálogo mudar, preserve a interpretação de ofertas e pedidos históricos: qual variante, versão, fornecedor e evidência estavam vinculados à operação. Planeje correção ou revalidação de registros existentes sem apagar sua origem. Se jogo ou simulação compartilham o domínio, mantenha regras coerentes e impeça que o teste dispare publicação, compra ou fabricação real sem autorização explícita.

### 5. Entregue uma base para produto e interface

Implemente em etapas pequenas e valide casos que distingam o contrato: combinação válida, variante incompatível, país ambíguo, informação ausente ou expirada e alteração de catálogo, conforme os riscos encontrados. Use dados controlados e não publique ofertas ou faça pedidos reais para testar sem autorização concreta.

Entregue um diagrama das relações, a matriz de regras e fontes, os problemas comprovados, as mudanças e as evidências. Inclua uma descrição curta do que o frontend agora pode mostrar: disponibilidade, fornecedor associado, motivos, validade da informação e ações de correção. Conclua quando o caminho comercial do escopo usar a mesma regra verificável e as lacunas restantes estiverem delimitadas. Separe sugestões visuais futuras das garantias já implementadas.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
