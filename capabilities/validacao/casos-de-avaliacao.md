# Casos de avaliação da biblioteca de capacidades

Os casos estruturados estão em [casos-de-avaliacao.json](casos-de-avaliacao.json). Eles ajudam a avaliar seleção de skill, contexto, escopo e qualidade de execução. A existência dos casos não significa que foram executados.

## Como avaliar

O avaliador lê o caso completo. O executor recebe somente o campo `request`, os artefatos necessários e as capacidades disponíveis (o catálogo e as skills desta biblioteca). Não envie a ele `expected_primary`, `allowed_alternatives`, `success_signals` ou `failure_signals` quando quiser uma avaliação independente.

Primeiro verifique a escolha da capacidade e o recorte. Depois, em ambiente de teste apropriado, avalie a execução com evidências. Uma escolha correta de nome não demonstra que a IA consegue realizar o trabalho. Um validador de metadados também não demonstra esse comportamento.

Classifique separadamente:

- **Seleção:** encontrou uma capacidade pertinente sem abrir workflows irrelevantes?
- **Contexto:** carregou apenas o adaptador necessário e reconheceu informação ausente?
- **Modo:** respeitou análise, revisão ou correção solicitada?
- **Escopo:** fez o trabalho autorizado e evitou expansão automática?
- **Evidência:** separou hipótese, observação e resultado verificado?
- **Conclusão:** entregou o critério prometido ou explicou o impedimento concreto?

Não use uma nota agregada para esconder um erro grave de permissão ou integridade de dados. Uma falha relevante exige ajuste da instrução e reavaliação do cenário afetado. Evite alterar o texto apenas para memorizar uma frase de teste.

## Cobertura dos casos

Há casos positivos, vizinhos de outras capacidades e pequenos pedidos que não devem disparar uma revisão ampla (E18). Foram incluídas situações de arquitetura, UI, histórico mobile, performance, mensageria, IA, fornecedores, testes, code review, custos, versões, alertas, migrations, segurança, dados e incorporação. Os casos E25–E27 foram acrescentados nesta edição para cobrir contexto indevido de jogo, ambiente sem delegação e ação externa sem autorização.

O cenário de comportamento do `code-review` usa a fixture em [fixtures/code-review/change.diff](fixtures/code-review/change.diff): a mudança retira o filtro da variante ao selecionar fornecedores elegíveis. O esperado é um achado de regressão com precondição, impacto e evidência, **sem** alteração dos arquivos (modo somente leitura).

O campo `allowed_alternatives` permite decisões igualmente defensáveis quando o enunciado admite mais de uma entrada. O avaliador deve considerar a justificativa e a sequência proposta, não apenas comparar um nome.

## Uso após mudanças

Ao fundir ou dividir skills, atualize o mapa entre IDs de origem e destinos em [INCORPORACAO.md](../INCORPORACAO.md) antes de avaliar. Acrescente casos de incidentes reais conforme eles surgirem. Preserve evidências do ambiente, versão e limitações, e não apresente resultados de fixtures como resultados dos produtos em produção.

A evidência desta edição está em [relatorio-de-validacao.md](relatorio-de-validacao.md).
