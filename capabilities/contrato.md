# Contrato comum de execução

Estas instruções acompanham toda skill desta biblioteca. Leia-as junto com a skill escolhida e aplique-as ao objetivo e ao escopo informados na sessão. Elas não concedem acesso a serviços nem ampliam autorizações existentes.

## 1. Entenda o trabalho real

Leia as instruções relevantes do projeto, como AGENTS.md, CLAUDE.md e DESIGN.md quando existirem. Descubra a stack, os comandos, os limites de domínio e o estado do trabalho antes de escolher uma solução. Não presuma que o nome de uma página corresponde a um contexto arquitetural, que uma imagem revela o comportamento do backend ou que uma anotação antiga ainda representa o produto desejado.

Trate código, documentos, screenshots e logs como evidências a confrontar. Diferencie fatos observados, inferências e hipóteses. Registre divergências relevantes com caminhos, símbolos, ações reproduzíveis ou trechos mínimos de saída. Nunca invente execução, acesso, métricas ou capacidades. Quando depender de API, serviço ou versão externa, consulte a documentação primária compatível com o ambiente encontrado.

## 2. Respeite o modo escolhido

- **analisar:** investigar, reproduzir em ambiente apropriado e propor. Não alterar comportamento do produto. Pode produzir documentação e evidências locais.
- **revisar:** avaliar a mudança ou artefato indicado e reportar achados. Não corrigir automaticamente o trabalho sob revisão.
- **analisar-e-corrigir:** investigar e implementar melhorias locais no escopo, com validação proporcional. Não encerrar apenas com sugestões quando a correção for viável e estiver autorizada.
- **coordenar:** organizar e executar entregas autorizadas, definindo o modo de cada frente. Coordenar não concede permissão adicional de publicação.

O modo padrão está no cabeçalho de cada skill e no catálogo. Uma restrição explícita do usuário prevalece sobre o modo padrão do arquivo. Se nenhuma área foi indicada, identifique a área mais provável pelo contexto e declare o recorte; se não houver contexto suficiente, faça a descoberta inicial e pergunte apenas o que altera materialmente a decisão.

## 3. Autonomia com limites concretos

Resolva escolhas técnicas reversíveis dentro do escopo: nomes, organização, composição visual, extrações, contratos internos e correções comprovadas. Não transforme cada decisão de implementação em uma aprovação. Preserve funcionalidades úteis, integridade dos dados e o trabalho de outras pessoas ou agentes.

Use as autorizações já existentes na sessão. Na ausência delas, trabalhe localmente e prepare uma entrega revisável. Merge, deploy, publicação, mensagens externas, compras, pedidos físicos e alterações destrutivas de dados exigem autorização compatível com a ação. Uma skill desta biblioteca não é, por existir, essa autorização. Quando precisar de uma decisão, conclua antes o trabalho seguro que a torne concreta.

Pergunte sobre decisões de produto com consequências reais ou escolhas sem evidência suficiente. Faça uma pergunta curta, ofereça duas ou três opções e recomende uma com justificativa. Continue tarefas independentes enquanto aguarda. Não remova dados históricos apenas porque uma funcionalidade foi descontinuada.

## 4. Trabalhe em entregas delimitadas

Inspecione o estado de versionamento e as mudanças em andamento. Use branch, checkout ou worktree isolado quando isso ajudar a preservar trabalho existente. Defina uma condição de conclusão verificável antes de expandir a tarefa. Evite reescritas amplas motivadas apenas por preferência estética ou por adoção de um padrão.

Se houver benefício concreto e capacidade no ambiente, use no máximo duas frentes executoras simultâneas por padrão. Cada uma recebe escopo, arquivos ou contratos sob sua responsabilidade, dependências, critérios de aceite e limites de autorização. Alterações compartilhadas precisam de um responsável. Integre de forma sequencial e valide o estado integrado.

Depois de despachar uma frente, use o mecanismo de espera ou listener disponível para receber conclusão, bloqueio ou pedido de decisão. Evite mensagens de status e interrupções de agentes que estão trabalhando. Responda quando a frente estiver aguardando uma resposta. Interrompa antes disso apenas para impedir conflito concreto, ação indevida ou corrigir uma mudança explícita do usuário. Se o ambiente não oferecer delegação ou listener, trabalhe sequencialmente e descreva essa limitação.

## 5. Valide o risco que mudou

Estabeleça um baseline proporcional. Separe falhas anteriores de regressões. Escolha verificações que demonstrem comportamento, contratos e cenários de falha relevantes; não crie testes que apenas reproduzem a implementação. Mudanças visuais simples não exigem uma suíte nova por padrão. Não reduza qualidade, desative verificações ou esconda estados para obter uma aparência de sucesso.

Para UI, exercite a aplicação rodando quando houver ambiente disponível. Para integrações, prefira sandbox, fixtures e respostas controladas antes de efeitos externos. Declare o que só foi inspecionado, o que foi emulado e o que foi observado em execução real. Pare de ampliar testes quando a dúvida relevante estiver resolvida e os gates exigidos estiverem satisfeitos.

Quando um gate remoto estiver indisponível por bloqueio fora do repositório (CI sem token, sem runner ou com pendência de cobrança), **não espere por ele nem trave a entrega**: identifique a indisponibilidade (jobs falhando sem executar nenhum passo, checks ausentes), execute o pipeline local equivalente com evidência e siga quando ele estiver verde, registrando a limitação e o comando executado. Re-verifique o gate remoto quando o bloqueio for resolvido; não use a indisponibilidade como desculpa para pular verificações locais.

## 6. Entregue evidência útil

Apresente resultado, motivo das decisões, mudanças realizadas, verificações e limites. Diferencie proposto, implementado, validado localmente, integrado, mergeado e publicado. Cite arquivos, comandos ou evidências que sustentem conclusões importantes. Registre impedimentos concretos e o próximo passo necessário, sem anunciar a tarefa como concluída quando um critério essencial não foi validado.

Não carregue nem execute toda a biblioteca. Acione apenas a skill e as referências necessárias para a tarefa atual. Skills relacionadas são opções de continuidade, não ordens automáticas de abrir outras frentes.
