# Fontes e limites conceituais

Fontes primárias consultadas em 4 de novembro de 2026. As skills desta biblioteca são uma síntese original das necessidades descritas pelo usuário e de práticas de investigação e entrega; não reproduzem capítulos, normas ou documentação de serviços.

## Stratified design

O nome correto do conceito tratado nesta biblioteca é **stratified design**. A referência bibliográfica é **Grokking Simplicity: Taming Complex Software with Functional Thinking**, de **Eric Normand**.

- [Página oficial do livro na Manning](https://www.manning.com/books/grokking-simplicity).
- [More about Stratified Design, do próprio Eric Normand](https://ericnormand.me/podcast/more-about-stratified-design).

O conceito orienta a análise de camadas de significado construídas sobre operações de menor nível. A leitura de ações, cálculos e dados é complementar. A aplicação desta biblioteca não transforma essas ideias em uma árvore obrigatória de diretórios. Exemplos e escolhas sobre um projeto concreto precisam ser justificados pelo código observado.

## Organização de skills

- [Especificação de Agent Skills](https://agentskills.io/specification).

A especificação descreve uma pasta com SKILL.md, metadados e recursos opcionais, além do carregamento progressivo de conteúdo. É uma referência de interoperabilidade. O repositório de destino pode ter outro formato, validadores próprios e suporte diferente de ferramentas. As skills desta biblioteca usam pastas com SKILL.md e frontmatter próprio; a conversão para o formato de um agente específico deve preservar semântica e autorizações.

## Acessibilidade

- [WCAG 2.2, recomendação do W3C](https://www.w3.org/TR/WCAG22/).

Use os critérios aplicáveis como referência quando uma revisão exigir avaliação normativa. Os prompts pedem evidências de barreiras e verificações relevantes, sem declarar conformidade integral a partir de uma amostra de telas ou de um scanner automático.

## Performance de renderização

- [Rendering performance, web.dev](https://web.dev/articles/rendering-performance).

A referência ajuda a distinguir trabalho de JavaScript, layout, pintura e composição. As metas de uma aplicação devem considerar dispositivos, interações e taxas de atualização efetivas. Esta biblioteca não fixa um FPS ou timeout universal e exige comparação em condições equivalentes.

## Bots e mensageria

- [Bots FAQ, Telegram](https://core.telegram.org/bots/faq).

É um ponto de entrada oficial para modos de recebimento e limites operacionais. Consulte a documentação vigente e as respostas reais da API na execução de `notificacoes-e-bots`. O pacote não fixa limites numéricos, não atribui falhas a banimento sem evidência e não trata contador de erros como contador de mensagens enviadas.

## Fontes específicas do projeto

Documentação de fornecedores, Phoenix, LiveView, Oban, frameworks de teste e provedores deve ser consultada na versão realmente usada pelo projeto. Nenhuma URL de fornecedor foi inventada a partir de um nome citado na conversa.

Preferências visuais, exemplos das casas e intenções comerciais nos contextos vêm dos relatos do usuário. Eles orientam a investigação, mas não constituem prova do estado atual do código. Não recebemos os repositórios dos produtos para esta entrega.
