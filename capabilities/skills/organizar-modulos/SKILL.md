---
name: "organizar-modulos"
title: "Organização de módulos, nomes e APIs internas"
category: "arquitetura"
default_mode: "analisar-e-corrigir"
origem: ["P05"]
related: ["revisar-arquitetura", "stratified-design", "consolidar-codigo", "migracoes-e-compatibilidade"]
description: "Use quando nomes confundem, módulos estão em contextos inadequados ou funções públicas e privadas não expressam corretamente as responsabilidades. Se ainda não estiver claro quais contextos deveriam existir, comece por revisar-arquitetura."
---

# Organização de módulos, nomes e APIs internas

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando nomes confundem, módulos estão em contextos inadequados ou funções públicas e privadas não expressam corretamente as responsabilidades. Se ainda não estiver claro quais contextos deveriam existir, comece por revisar-arquitetura.

## Entradas úteis

- Contexto ou conjunto de módulos a revisar; sem indicação, proponha um recorte a partir dos problemas encontrados.
- Convenções já estabelecidas e consumidores que exigem compatibilidade.
- Vocabulário do produto ou exemplos de nomes que causam confusão.

## Instrução

Revise os nomes, a localização e as interfaces dos módulos no escopo informado. Quero que a organização ajude uma pessoa a encontrar responsabilidades e entender o código, preservando os contratos relevantes. Analise o significado das mudanças antes de reorganizar arquivos.

### Descubra o vocabulário e os consumidores

Leia as convenções do projeto e identifique os termos usados no domínio, na interface e nas integrações. Procure nomes que descrevem a responsabilidade real, nomes genéricos que escondem decisões e termos iguais usados com sentidos diferentes.

Mapeie quem chama cada módulo candidato, o que ele oferece e quais dependências conhece. Além de referências textuais, investigue registros dinâmicos, reflexão, injeção de dependências, plugins, callbacks, configuração, serialização e identificadores armazenados em filas ou banco. Um símbolo sem chamada direta não é necessariamente privado ou inutilizado.

Observe convenções exigidas pelo framework ou linguagem na versão instalada. Não renomeie callbacks ou pontos de descoberta automática como se fossem métodos comuns. Registre consumidores externos ou persistidos cuja compatibilidade precisa ser preservada.

### Diferencie os tipos de problema

Classifique os candidatos: nome impreciso, responsabilidade fora do contexto, API excessiva, função escondida no módulo errado, duplicação de regra, dependência indevida ou organização física pouco navegável. Mostre um exemplo concreto para cada mudança relevante.

Uma pasta grande pode precisar de agrupamento, mas o tamanho não é justificativa suficiente. Crie subgrupos por responsabilidade compreensível e motivo de mudança. Evite níveis de diretório que apenas repetem palavras, fragmentação por arquivo e categorias vagas como um novo depósito de utilitários.

Questione tanto módulos concentradores quanto fragmentação excessiva. Aproximar funções relacionadas pode ser melhor do que extraí-las. Não use o nome de uma tela como fronteira de domínio sem examinar suas responsabilidades.

### Reavalie o contrato público

Para cada função pública relevante, identifique seu consumidor, sua promessa e os detalhes que ela deveria esconder. Verifique entradas, saídas, erros, efeitos e contexto de autorização. Tornar uma função pública cria uma obrigação de manutenção; não faça isso apenas para facilitar um teste.

Considere mover uma função privada quando ela representar uma responsabilidade própria de outro módulo. Nesse caso, desenhe primeiro a interface que o novo proprietário deveria oferecer. Evite expor detalhes internos e transferir dados desnecessários entre contextos apenas para reduzir linhas de um arquivo.

Avalie se uma função pública pode se tornar privada ou desaparecer quando não houver consumidores legítimos. Para APIs usadas fora do recorte, ofereça compatibilidade temporária quando necessária e defina como verificar que a transição terminou.

### Execute uma sequência segura e legível

Prepare um mapa curto de nome atual, destino, motivo, consumidores e estratégia de migração. Separe renomeações mecânicas de mudanças de comportamento para tornar a revisão compreensível. Respeite trabalho em andamento e o isolamento previsto no projeto.

No modo de correção, implemente por conjuntos coerentes. Atualize imports, aliases, configuração, documentação de contratos, testes relevantes e mecanismos de descoberta. Considere a coexistência de versões durante implantação e a execução de trabalhos já persistidos com nomes antigos.

Não remova uma ponte de compatibilidade apenas porque a busca no código atual ficou vazia. Verifique os consumidores que sobrevivem ao deploy ou registre a pendência de modo explícito, sem inventar evidência de produção.

### Valide a organização e conclua

Execute as verificações necessárias para os caminhos afetados. Compile ou carregue a aplicação conforme sua tecnologia e percorra ao menos os fluxos que exercitam contratos movidos. Use testes específicos para referências dinâmicas ou persistidas quando esse for o risco da mudança.

Entregue o mapa final, a árvore relevante e os motivos de cada agrupamento. Mostre quais interfaces ficaram públicas, quais foram reduzidas e como os consumidores continuam funcionando. Registre aliases temporários e seus critérios de remoção.

Conclua quando o recorte estiver navegável, os nomes expressarem responsabilidades e os consumidores afetados estiverem atualizados ou protegidos por compatibilidade explícita. Não continue renomeando por preferência estética depois que o problema identificado estiver resolvido.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
