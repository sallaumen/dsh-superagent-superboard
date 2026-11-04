---
name: "build-ci-dependencias"
title: "Revisar dependências, build e confiabilidade da CI"
category: "qualidade"
default_mode: "analisar-e-corrigir"
origem: ["P31"]
related: ["coordenar-entregas", "performance", "estrategia-de-testes", "investigar-bugs", "validar-entrega"]
description: "Use quando o ambiente não é reproduzível, o build diverge entre máquinas, a CI oscila ou dependências precisam de manutenção fundamentada. Preserva o significado dos checks; não é uma ordem de atualizar tudo para a última versão."
---

# Revisar dependências, build e confiabilidade da CI

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando o ambiente não é reproduzível, o build diverge entre máquinas, a CI oscila ou dependências precisam de manutenção fundamentada. Não é uma ordem de atualizar tudo para a última versão.

## Entradas úteis

- Comando ou pipeline afetado e logs sem segredos.
- Plataformas suportadas e atualizações já planejadas, se houver.

## Instrução

Investigue a confiabilidade do ambiente de desenvolvimento, das dependências e do pipeline de entrega no recorte indicado. Corrija causas demonstradas e reduza trabalho repetitivo. Preserve o significado dos checks; obter uma execução verde desativando verificações importantes não atende ao objetivo.

### Reconstrua o caminho de execução

Leia manifests, lockfiles, configuração de runtime, scripts de build, contêineres e workflows relevantes. Descubra os comandos realmente usados por desenvolvedores e pela CI. Compare versões de ferramentas, sistema operacional, variáveis necessárias, serviços auxiliares, artefatos e permissões.

Reproduza a falha em ambiente isolado quando possível. Diferencie erro determinístico, intermitência, recurso indisponível, configuração ausente e divergência de ambiente. Não instale ferramentas globalmente nem modifique o ambiente compartilhado sem necessidade; use os mecanismos já previstos pelo projeto.

Mapeie de onde vêm dependências, como versões são resolvidas e o que torna o build repetível. Verifique uso correto dos lockfiles, geração de arquivos e caches. Um cache pode acelerar o trabalho e também esconder incompatibilidades; confirme a chave e o critério de invalidação antes de recomendar limpá-lo em toda execução.

### Escolha manutenção com propósito

Classifique dependências relevantes: usadas, possivelmente obsoletas, substituíveis ou necessárias por contrato indireto. Procure consumidores dinâmicos, plugins e ferramentas de build antes de concluir que um pacote não é utilizado. Não remova dependências apenas porque não encontrou um import comum.

Para atualizações propostas, verifique compatibilidade com o runtime, documentação oficial e mudanças relevantes à versão adotada. Diferencie correção necessária, atualização de manutenção e mudança maior com impacto de produto. Não acumule upgrades independentes no mesmo lote apenas para reduzir a quantidade de PRs.

Analise a CI como um fluxo: etapas duplicadas, dependências artificiais, serialização desnecessária, artefatos ausentes, testes instáveis e uso excessivo de recursos. Priorize o que reduz falhas ou espera recorrente com evidência. Ganhos de tempo devem ser medidos em condições comparáveis, reconhecendo a variação do provedor.

### Corrija sem esconder o problema

Implemente lotes que permitam atribuir mudanças de comportamento. Mantenha a relação entre código, lockfile e artefato gerado. Se substituir um script, preserve entradas, saídas e códigos de erro que consumidores utilizam.

Investigue testes intermitentes por isolamento, tempo, concorrência, ordem, rede e dados compartilhados. Aumentar timeout ou repetir um teste até passar só é justificável quando a causa e o risco estão compreendidos. Uma quarentena temporária precisa de motivo, responsável e condição de saída; não a trate como solução definitiva.

Evite publicar artefatos, releases ou imagens como efeito incidental de um diagnóstico. Inspecione gatilhos e permissões dos workflows antes de dispará-los. Não imprima tokens ou variáveis secretas para comparar ambientes. Use logs sanitizados e informações de presença ou configuração quando suficientes.

### Valide e entregue

Execute os comandos afetados com a configuração suportada. Verifique um caminho limpo e, quando o problema envolver cache, o caminho com cache relevante. Faça testes de compatibilidade proporcionais às plataformas realmente suportadas; não invente uma matriz de versões sem compromisso do projeto.

Apresente a causa, mudanças, versões envolvidas, antes e depois quando medido, e limitações de reprodução. Documente apenas os comandos e pré-requisitos que ajudam a próxima pessoa a repetir o resultado. Separe verificação local de execução efetiva no provedor de CI.

Conclua quando o problema delimitado estiver corrigido e o pipeline continuar verificando o que deveria. Se faltarem credenciais ou acesso ao runner, deixe as alterações e o procedimento revisáveis, indicando exatamente qual confirmação ainda é necessária. Registre melhorias independentes sem abrir uma manutenção ilimitada de todo o ecossistema.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
