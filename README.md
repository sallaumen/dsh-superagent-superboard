<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="priv/static/favicon.svg">
    <img src="priv/static/images/superboard-mark.svg" width="80" height="80" alt="">
  </picture>
</p>
<h1 align="center">Super Agent Super Board</h1>
<p align="center"><strong>Um painel local para acompanhar issues, pull requests e o trabalho dos agentes no GitHub.</strong></p>
<p align="center">Português · <a href="README.en.md">English</a></p>

O **Super Board** é o painel deste repositório. Ele reúne, por projeto, o que está na fila, o que está em execução e o que precisa de uma decisão sua. **Você pode usá-lo só com o GitHub**, sem instalar o DeepSeek Harness, sem configurar um agente e sem uma chave de IA para consultar os dados sincronizados.

O **[DeepSeek Super Agent](https://github.com/deepseek-ai/dsh-superagent-prototype)** é um projeto separado da DeepSeek. O nome do software é `dsh-superagent`. Ele roda dentro do **[DeepSeek Harness](https://www.deepseek.com/en/harness/)** e pode executar uma tarefa de programação e devolver um pull request. É opcional: **você administra o trabalho pelo painel; o agente executa o que lhe for atribuído**.

**Por onde começar:** [Instalar só o painel](#instalar-o-painel) · [Baixar e conectar o agente](#instalar-e-conectar-o-agente) · [Dividir um pedido](#de-um-pedido-a-várias-issues) · [Entender o paralelismo](#como-ler-o-paralelismo).

![Painel do projeto catálogo: duas tarefas em execução, duas na fila e uma pergunta aguardando resposta.](docs/assets/readme/board.png)

*Captura real do painel com um projeto de exemplo. A tarefa “Definir quais campos são públicos” aparece em **Precisa de você**: é ali que você abre a conversa para desbloquear o trabalho.*

## Por que criamos o painel

Uma issue guarda o pedido. O PR mostra o código. Os checks dizem se ele passou. Quando há vários projetos ou agentes em paralelo, ainda sobra uma pergunta: **qual trabalho precisa de mim agora?** O board aproxima esses registros sem tirar o GitHub do fluxo. Você pode abrir a tarefa que parou, ler a pergunta do agente e decidir o próximo passo. Se fechar o painel, o agente continua trabalhando em seu próprio processo.

| O que você quer fazer | O que precisa configurar |
| --- | --- |
| Acompanhar issues, PRs, revisões, checks, merges e atividade de vários repositórios | Painel + acesso de leitura no GitHub. |
| Criar uma issue a partir de um pedido | Acesso de escrita no repositório. Você revisa antes de publicar. |
| Refinar um pedido, propor subtarefas com critérios de aceite ou fazer perguntas que exigem um modelo | Um provedor para a **IA do painel**. Ela é independente do super agent. |
| Delegar implementação, acompanhar tickets, ler relatórios e ver vagas de execução | DeepSeek Harness + um perfil do `dsh-superagent` para o repositório. Claude Code e Codex também podem ser configurados como executores locais alternativos. |
| Consultar o dia, usar o Chat, revisar consumo e custos | O Chat oferece **SuperBoard Skills** para consultar o estado salvo; informações de uso dependem da fonte conectada. Entrada por texto e saída de voz pelo navegador não exigem ElevenLabs. |

## Instalar o painel

Você vai precisar de **Git, Elixir 1.19 / Erlang OTP 27 e PostgreSQL 16**. Os comandos abaixo usam o banco local de desenvolvimento. Se já tem PostgreSQL, use a [configuração local](docs/operations.md#local-secrets); se prefere Docker, pode criar o banco assim:

```sh
docker run --name dsh-board-postgres \
  -e POSTGRES_USER=board -e POSTGRES_PASSWORD=board \
  -e POSTGRES_DB=agent_board_dev -p 127.0.0.1:5434:5432 -d postgres:16
```

1. Baixe **este painel** e prepare a configuração:

   ```sh
   git clone https://github.com/sallaumen/dsh-superagent-superboard.git
   cd dsh-superagent-superboard
   cp .env .env.local
   ```

2. Em `.env.local`, defina `GITHUB_TOKEN` com acesso aos repositórios desejados. Para apenas acompanhar, basta acesso de leitura; para publicar issues, o token precisa poder criá-las. Mantenha esse arquivo fora do Git. Inicie o painel:

   ```sh
   mix setup
   PORT=4002 mix phx.server
   ```

3. Abra **[localhost:4002](http://127.0.0.1:4002)**. Em **Configurações → Projetos → Adicionar projeto**, informe `dono/repositório`. Para usar só o GitHub, deixe desmarcada a opção de criar um agente. Depois da sincronização, abra o projeto na lateral para conferir as issues e os PRs. Se não aparecerem, veja a última sincronização em **Configurações → Sistema → Atividade**.

O idioma da interface pode ser trocado em **Settings → System → Board language**. Em **Configurações → IA e setup**, a verificação mostra o que está pronto para cada integração e guarda a data do último resultado. Uma IA ausente afeta os recursos de IA; ela não impede a consulta ao GitHub. Para manter o painel rodando no macOS, veja [como instalar o serviço](docs/operations.md#run-as-a-service).

## Instalar e conectar o agente

Faça esta parte se quiser que alguém possa mencionar a conta do agente em uma issue e receber uma implementação em um PR. O fluxo começa com **dois downloads diferentes**:

1. **[Baixe o DeepSeek Harness](https://www.deepseek.com/en/harness/)**, o ambiente que hospeda as sessões. Configure um provedor de modelo para o Harness. A chave configurada no board não configura automaticamente esse perfil.
2. **[Baixe o DeepSeek Super Agent](https://github.com/deepseek-ai/dsh-superagent-prototype)**, o pacote que observa um repositório e coordena seus executores. No terminal:

   ```sh
   git clone https://github.com/deepseek-ai/dsh-superagent-prototype.git
   cd dsh-superagent-prototype
   ```

3. **Instale e configure o pacote.** Abra essa pasta no seu assistente de código e peça: *“Leia o SETUP.md deste repositório e configure o dsh-superagent comigo.”* O [roteiro oficial de instalação](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/SETUP.md) cobre repositório, conta GitHub separada para o bot, quem pode acioná-lo e política de trabalho. Se preferir o terminal, siga a [instalação manual oficial](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/docs/006-deployment.md#install), incluindo o perfil dedicado e a inicialização. **Clonar o repositório sozinho não inicia o agente.**
4. **Conecte ao board.** Na máquina em que o Harness está instalado, abra **Configurações → Projetos** no board. Adicione o perfil detectado ao projeto correspondente. Para outro repositório, veja [como configurar um segundo perfil](docs/agent/setup.md#a-second-repository-optional). Em **IA e setup**, confira se o agente responde.
5. **Faça o primeiro teste.** De uma conta autorizada, abra uma issue pequena, mencione a conta do seu bot e diga qual resultado espera. Acompanhe o ticket no painel e a resposta na issue. A [verificação da instalação](docs/agent/setup.md#5-verify-it-is-configured-and-alive) ajuda a distinguir um agente parado de um agente ocioso.

**Pré-requisitos do agente:** Node.js 22.19+ ou 24+, pnpm, Git 2.32+, Python 3.8+, tmux e GitHub CLI 2.48+, além de um clone local do repositório de trabalho. Os executores rodam com os privilégios do usuário do sistema; o [guia de implantação](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/docs/006-deployment.md) explica como isolar contas e credenciais. Para identificar as sessões como `SIGLA - Nome da tarefa`, use **Configurações → IA e setup → Nomes das sessões do Harness**.

## De um pedido a várias issues

Em **Novo pedido**, descreva o resultado desejado. Você pode enviá-lo como **uma issue** ou escolher **Dividir automaticamente**. Com a IA do painel configurada, o board propõe tarefas com título, descrição, critérios de aceite, tamanho e dependências. **Nada é publicado só porque você pediu a divisão.** Revise os títulos e os critérios, mantenha uma única issue se ela for suficiente e confirme o conjunto que deseja enviar.

![Revisão de uma divisão: medir o tempo de resposta do board é a primeira tarefa; corrigir o gargalo medido depende dela.](docs/assets/readme/split.png)

*Captura real do modo de ensaio, sem chamada paga e antes de criar qualquer issue.*

No exemplo, **medir o tempo de resposta** pode começar já. **Corrigir o gargalo medido** depende da primeira tarefa: executar as duas ao mesmo tempo seria pedir uma correção antes do diagnóstico. O board mantém essas relações e agrupa a divisão em um objetivo. Quando há um agente conectado, ele só é chamado na tarefa dependente depois da liberação dos pré-requisitos. As tarefas independentes podem ocupar vagas distintas.

## Como ler o paralelismo

![Indicador Paralelismo: 2 de 4 vagas em uso, com 2 tickets esperando.](docs/assets/readme/parallelism.png)

**“2 de 4”** significa que o orquestrador informou **dois executores ocupados de quatro permitidos naquele instante**. **“2 tickets esperando”** é a fila informada separadamente. Use **− / +** no cartão para ajustar o limite daquele agente. Aumentar o limite não elimina dependências nem responde a uma pergunta pendente. Quando a fonte está indisponível, o painel mostra **`?`**, não zero. A captura usa uma resposta de exemplo do orquestrador.

Para avaliar entrega, veja **Vazão**: tarefas concluídas, PRs mesclados, commits e tempo de ciclo ajudam a distinguir “mais executores ocupados” de “mais trabalho entregue”. As [definições das métricas](docs/maintainer-contract.md#throughput) explicam a fonte e as janelas de cada número.

## Guias por assunto

| Se você quer… | Abra |
| --- | --- |
| Entender como uma menção vira ticket, execução e PR | [O ciclo do agente](docs/agent/how-it-works.md) |
| Configurar modelos, limites de gasto e recursos de IA | [IA do painel](docs/ai-layer.md) · [Custos](docs/operations.md#what-it-costs) |
| Usar Chat, ditado, voz e atalhos | [Chat e voz](docs/voice-conversation.md) |
| Diagnosticar dados atrasados ou serviços locais | [Operação e solução de problemas](docs/operations.md#when-something-is-wrong) |
| Integrar ou contribuir | [API JSON](docs/api.md) · [Arquitetura](docs/architecture/README.md) · [Contribuição](CONTRIBUTING.md) · [CI](PIPELINES.md) |
