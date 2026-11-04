# Contexto técnico: Elixir, Phoenix, LiveView e Oban

Use somente quando a stack estiver confirmada no repositório. Descubra versões, extensões e convenções reais antes de prescrever APIs ou comandos.

## Arquitetura e organização

Leia a aplicação OTP, sua supervisão, contextos, módulos públicos, schemas, endpoints e componentes relevantes. Não mapeie uma tela automaticamente para um contexto de domínio nem crie processos para funções que só fazem cálculos. Separe escolhas de concorrência e ciclo de vida das escolhas de organização de código.

Ao renomear ou mover módulos, procure referências em configuração, behaviours, callbacks, supervisores, serialização, dispatch dinâmico, jobs persistidos, agendamentos e migrações. Uma busca por chamadas diretas não comprova que um módulo está sem uso. Não exponha funções apenas para facilitar testes; uma API pública precisa de responsabilidade e contrato.

Use stratified design como análise dos níveis de significado e de como funções se apoiam umas nas outras. Ações, cálculos e dados constituem uma leitura complementar. Nenhuma delas exige por si só criar pastas com esses nomes ou abandonar convenções úteis da aplicação.

## LiveView e atualizações

Investigue o fluxo entre evento do usuário, estado do servidor, mensagem assíncrona, atualização e feedback visual. Confira assinaturas, cancelamento e limpeza de recursos quando a tela muda ou reconecta. Respostas antigas não podem sobrescrever uma seleção nova.

Procure trabalho bloqueante, consultas repetidas, excesso de dados enviados e atualizações que recriam elementos desnecessariamente. Otimize com evidência, preservando persistência e recuperação de conexão. Não atribua todo freeze a LiveView sem perfil e reprodução.

## Jobs e IA

Leia a configuração e os contratos efetivos do Oban e dos workers. Concorrência de fila, execução de job e capacidade global de IA são limites diferentes. Verifique como retries, cancelamentos, falhas e duplicações interagem com efeitos externos.

Mapeie workers que podem usar IA e valide o uso real em runtime. Trate execução condicional, delegação e subprocessos sem dupla contagem. Não assuma que todos os workers de uma fila usam IA ou que um nome de fila prova o consumo.

Ao alterar contrato de worker ou payload, considere jobs já persistidos. Consulte documentação oficial da versão encontrada para limites, APIs e garantias. Não prometa idempotência de uma operação externa apenas porque o job tem alguma regra de unicidade.

## Validação

Descubra os comandos adequados no projeto. Use testes de domínio e integração nos pontos em que contratos mudaram, e cenários em execução para navegação, reconexão e feedback. Preserve isolamento de banco, tempo, filas e mensagens quando isso afetar testes. Não imponha uma matriz inteira de ferramentas ou um novo framework de testes por preferência.

Skills associadas: revisar-arquitetura, stratified-design, organizar-modulos, performance, estados-assincronos, orquestracao-ias, testes-redundantes, estrategia-de-testes e migracoes-e-compatibilidade.
