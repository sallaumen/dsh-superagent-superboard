---
name: "stratified-design"
title: "Stratified design e clareza dos níveis de abstração"
category: "arquitetura"
default_mode: "analisar-e-corrigir"
origem: ["P04"]
related: ["revisar-arquitetura", "organizar-modulos", "estrategia-de-testes"]
description: "Use quando funções misturam decisões de negócio, detalhes técnicos e efeitos, ou quando é difícil entender uma operação sem atravessar muitos níveis de código. Aprofunda um recorte; a revisão dos limites de domínio do sistema inteiro pertence a revisar-arquitetura."
---

# Stratified design e clareza dos níveis de abstração

> Regras comuns: aplique o [contrato.md](../../contrato.md) e o modo padrão desta skill (`analisar-e-corrigir`). Uma instrução explícita da sessão prevalece.

## Quando usar

Quando funções misturam decisões de negócio, detalhes técnicos e efeitos, ou quando é difícil entender uma operação sem atravessar muitos níveis de código. Esta skill aprofunda um recorte; uma revisão dos limites de domínio do sistema inteiro pertence a revisar-arquitetura.

## Entradas úteis

- Fluxo, módulo ou regra a estudar. Sem indicação, escolha um caminho importante com mistura de níveis demonstrável.
- Interesse em explicação didática ou foco apenas na implementação.
- Restrições de comportamento e compatibilidade que precisam ser preservadas.

## Instrução

Analise e refine o escopo informado usando stratified design como uma ferramenta de compreensão e organização. A referência conceitual é o livro Grokking Simplicity: Taming Complex Software with Functional Thinking, de Eric Normand. Quero uma aplicação criteriosa ao código existente, com decisões explicadas e melhorias demonstráveis.

### Observe os níveis de significado presentes

Leia um fluxo real de ponta a ponta. Identifique quais operações expressam intenção do produto, quais realizam decisões intermediárias e quais lidam com representação de dados, bibliotecas, persistência, rede ou outros mecanismos. Observe onde um leitor precisa alternar repetidamente entre esses níveis para compreender uma única função.

Desenhe um pequeno mapa de chamadas do recorte e anote o significado de cada grupo de operações. Use-o para mostrar onde as dependências atravessam uma abstração, onde detalhes vazam para consumidores e onde uma camada existente apenas acrescenta indireção.

Faça também uma análise de ações, cálculos e dados. Identifique operações dependentes do momento ou da quantidade de execuções, transformações determinísticas e representações de informação. Essa classificação é uma segunda perspectiva: não a confunda com uma exigência de três camadas físicas ou três diretórios obrigatórios.

### Avalie a qualidade das abstrações

Procure funções que consigam ser lidas por meio de operações de significado coerente, sem esconder decisões relevantes. Examine se uma abstração protege o consumidor de detalhes que realmente mudam e se sua interface é pequena o suficiente para ser compreendida.

Questione extrações que apenas trocam uma linha por uma chamada com nome vago. Uma função curta pode continuar misturando responsabilidades; uma função maior pode expressar um algoritmo coeso. Não persiga uma quantidade fixa de linhas, níveis ou arquivos.

Verifique se regras específicas dependem de operações estáveis e se componentes inferiores precisam conhecer detalhes indevidos dos seus consumidores. Considere colapsar níveis artificiais e aproximar código que muda junto. A simplicidade da solução deve ser avaliada pelo uso real, não pela aparência do diagrama.

### Proponha um recorte de melhoria

Escolha os pontos em que a reorganização oferece maior ganho de clareza ou segurança. Explique a intenção de cada limite, o detalhe que ele protege e o custo que introduz. Compare a alternativa proposta com manter o código próximo e explícito.

Quando fizer sentido, separe cálculo de efeitos para permitir raciocínio e verificação independentes. Mantenha nas bordas informações necessárias, como tempo, identificadores, resultados externos e configuração. Não force a passagem de inúmeros parâmetros ou uma estrutura de dependências complexa apenas para declarar uma função pura.

Preserve semântica, ordem de efeitos, tratamento de erros e limites transacionais. Tornar uma decisão determinística não autoriza mudar quando ela ocorre, quais dados considera ou quantas vezes uma operação externa é executada.

### Implemente e explique a diferença

No modo de correção, refatore um recorte completo, atualizando seus consumidores. Faça extrações, mudanças de interface ou aproximações de código conforme a evidência exigir. Evite deixar uma arquitetura intermediária com caminhos concorrentes e responsabilidade ambígua.

Use exemplos de antes e depois para demonstrar como o leitor passa a acompanhar a intenção, onde permanecem os efeitos e o que pode ser alterado sem conhecer os detalhes internos. Explique as concessões feitas; não apresente o resultado como a única arquitetura correta.

Valide o comportamento que importa: decisões de domínio, limites, erros e efeitos observáveis. Adicione testes somente quando protegerem um risco real da mudança. Testes que reproduzem as chamadas privadas ou fixam o número de camadas não demonstram uma melhoria.

### Entrega e critério de conclusão

Entregue o mapa do recorte, os pontos de mistura encontrados, as decisões adotadas, os exemplos didáticos e as verificações executadas. Diferencie a aplicação prática da sua interpretação do conceito e cite fontes primárias quando atribuir uma regra específica ao autor.

Encerre quando o fluxo escolhido tiver níveis de significado mais coerentes, interfaces justificáveis e comportamento preservado com evidência. Registre oportunidades em outros módulos como continuação possível, sem transformar automaticamente este estudo em uma migração de todo o projeto.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
- Parâmetros e modos: [parametros.md](../../parametros.md)
- Contextos opcionais: somente os pertinentes, conforme [contextos/README.md](../../contextos/README.md)
- Fontes e conceitos: [referencias/fontes-e-conceitos.md](../../referencias/fontes-e-conceitos.md)
