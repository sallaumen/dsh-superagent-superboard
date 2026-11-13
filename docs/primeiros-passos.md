# Do primeiro repositório ao primeiro pedido

[English: setup](getting-started.md) · [English: first request](first-request.md) · [Visão geral](../README.pt-BR.md)

## Acompanhar um repositório

Para rodar o painel, instale o [Git](https://git-scm.com/downloads) e o [Elixir com Erlang/OTP](https://elixir-lang.org/install.html). Confira com `git --version` e `elixir --version`: o painel é testado com `Elixir 1.19` e `Erlang/OTP 27`. Para o banco, escolha **uma** opção: [PostgreSQL 16](https://www.postgresql.org/download/) ou [Docker](https://docs.docker.com/get-started/get-docker/) com o comando abaixo. O banco de desenvolvimento é `agent_board_dev`, em `127.0.0.1:5434`, com usuário e senha `board`. Se preferir Docker:

```sh
docker run --name dsh-board-postgres -d -p 127.0.0.1:5434:5432 \
  -e POSTGRES_USER=board -e POSTGRES_PASSWORD=board -e POSTGRES_DB=agent_board_dev postgres:16
```

1. Baixe o painel e prepare a configuração:

   ```sh
   git clone https://github.com/sallaumen/dsh-superagent-superboard.git
   cd dsh-superagent-superboard
   cp .env .env.local
   ```

2. Defina `GITHUB_TOKEN` em `.env.local` ([configurar token no GitHub](https://github.com/settings/tokens)). Em um token de acesso granular, selecione o dono e o repositório. Para acompanhar, permita leitura de conteúdo, issues, pull requests e checks; para publicar pedidos, use **Issues: read and write**. Esse token é do painel, não do bot. Mantenha esse arquivo fora do Git. Inicie o painel (se o Mix pedir para instalar Hex ou Rebar, aceite):

   ```sh
   mix setup
   PORT=4002 mix phx.server
   ```

3. Uma instalação nova começa **sem projetos**. Abra [localhost:4002](http://127.0.0.1:4002). Para mudar o idioma, use **Settings → System → Board language**. Em **Configurações → IAs e setup → Usar só o GitHub**, informe o dono e o nome do repositório e clique em **Acompanhar repositório**. Use campos separados: em `octocat/Hello-World`, o dono é `octocat` e o nome é `Hello-World`. Abra o projeto na lateral. A sincronização automática roda aproximadamente a cada cinco minutos; **Sem agente** é esperado nesse modo. Se continuar vazio, verifique **Configurações → Sistema → Atividade**.

## Conectar o Super Agent

Esta etapa é opcional. O [DeepSeek Harness](https://www.deepseek.com/en/harness/) hospeda as sessões; o [DeepSeek Super Agent](https://github.com/deepseek-ai/dsh-superagent-prototype) acompanha o repositório e coordena quem executa as tarefas.

| Na máquina do agente | Requisito |
| --- | --- |
| JavaScript | `Node.js 22.19+` na linha 22.x ou `24+`; `pnpm` |
| Repositório | `Git 2.32+`, `gh 2.48+` e um clone local do repositório |
| Execução | `Python 3.8+` e `tmux` |
| Conta | Uma conta GitHub separada para o bot, com acesso de escrita; um provedor de modelo configurado no perfil do Harness |

1. Instale o [comando do Harness](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/docs/006-deployment.md#install): `npm install -g @deepseek-ai/dsh@0.2.1-rc.3`. Confira com `dsh --version`. No Linux, use Debian com `procps`; o teste no Alpine não chegou ao fim.
2. Para o provedor padrão da API DeepSeek, defina `DEEPSEEK_API_KEY` no `.env.local` e reinicie o board. Para usar outro provedor, configure-o no [Harness](https://www.deepseek.com/en/harness/).
3. [Entre com a conta do bot](agent/setup.md#2-the-bot-identity) e confira o login do GitHub. Deixe o board criar o perfil do projeto.

Abra **Configurações → Projetos → Conectar o Super Agent** e escolha o caminho da sua máquina:

| O que você tem | Próximo passo |
| --- | --- |
| Um agente que já acompanha esse repositório | Use **Buscar perfis novamente**, escolha o perfil detectado e confirme **Adicionar ao board**. Não é preciso criar outro agente. |
| Nenhum agente ainda | Clone o **projeto que receberá o trabalho**, informe o dono, o nome e a pasta que contém o `.git`, depois escolha o limite de execuções. Revise e confirme a instalação. O bot precisa de escrita: conceda o acesso no repositório ou deixe o board fazer isso com um token que possa gerenciar colaboradores. |

Para instalar pelo terminal, siga o [guia oficial](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/SETUP.md). Veja também os [requisitos e permissões](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/docs/006-deployment.md#prerequisites).

**Teste uma tarefa real.** De uma conta autorizada, abra uma issue pequena e mencione o login real do bot. Em um repositório de jogo, por exemplo: “@seu-bot Documente um controle que já existe no README e abra um PR.” Confira a resposta na issue e, no painel, o ticket e o PR associado. Conectar o perfil por si só não envia tarefas.

## Do pedido às issues

Em **Novo pedido**, descreva o resultado: “O cliente consegue exportar o catálogo em CSV”. Para uma mudança pequena, envie uma issue. Para um pedido maior, escolha **Dividir automaticamente** com a IA do painel configurada. Revise títulos, critérios de aceite e dependências antes de confirmar a publicação.

Por exemplo: **definir as colunas do CSV** vem antes de **implementar a exportação**. Já **adicionar um ícone de download** pode acontecer em paralelo. As issues da divisão ficam agrupadas em um objetivo.

## Escolher um executor

O provedor que ajuda a planejar o pedido é independente do agente que escreve o código. Ao enviar um pedido, você pode aceitar a sugestão do painel ou escolher outro executor:

| Executor | Como começa |
| --- | --- |
| **DeepSeek Super Agent** | O bot recebe a menção na issue de um repositório que seu perfil acompanha. Tarefas dependentes aguardam a liberação dos pré-requisitos. |
| **Claude Code** | Escolha Claude Code para a tarefa e, ao abri-la, confirme a execução local com o comando `claude` já autenticado. |
| **Codex** | Escolha Codex e confirme a execução local com o comando `codex` já autenticado. É o caminho para programar com modelos GPT da OpenAI. |

Você pode mandar a implementação do CSV para Claude Code e um pedido separado sobre o ícone para Codex. A distribuição entre modelos é uma escolha sua. No cartão **Paralelismo**, `2 de 4` significa dois executores DeepSeek ocupados de quatro permitidos naquele perfil. A fila aparece à parte; `?` indica que o agente não informou o valor. Execuções locais de Claude Code e Codex não ocupam essas vagas.

## Conversar por voz

Abra o **Chat** (ou pressione **Espaço** duas vezes no board) e experimente uma **SuperBoard Skill** por texto. Para conversar por voz, configure `ELEVENLABS_API_KEY` em `.env.local`, reinicie o painel e abra **Configurações → Voz e resumo**. Escolha o microfone do board, selecione a voz e permita o uso do microfone no navegador.

Pergunte o que precisa da sua atenção. A **ElevenLabs Scribe** transcreve a pergunta; com as respostas faladas ativadas, você ouve uma versão curta ou completa e pode reler o texto no Chat. O áudio consome créditos da ElevenLabs. Para usar o Chat por texto, não é preciso configurar a voz. [Controles de voz e diagnóstico (em inglês)](voice-conversation.md)
