# Do primeiro repositório ao primeiro pedido

[English: setup](getting-started.md) · [English: first request](first-request.md) · [Visão geral](../README.pt-BR.md)

## Acompanhar um repositório

Para rodar o painel, instale `Git`, `Elixir 1.19`, `Erlang/OTP 27` e `PostgreSQL 16`. O banco de desenvolvimento é `agent_board_dev`, em `127.0.0.1:5434`, com usuário e senha `board`. Se preferir Docker:

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

2. Defina `GITHUB_TOKEN` em `.env.local` ([configurar token no GitHub](https://github.com/settings/tokens)). Acesso de leitura basta para acompanhar; para publicar pedidos, permita a criação de issues. Mantenha esse arquivo fora do Git. Inicie o painel:

   ```sh
   mix setup
   PORT=4002 mix phx.server
   ```

3. Abra [localhost:4002](http://127.0.0.1:4002). Para mudar o idioma, use **Settings → System → Board language**. Em **Configurações → IAs e setup → Usar só o GitHub**, informe o dono e o nome do repositório e clique em **Acompanhar repositório**. Depois da sincronização, abra o projeto na lateral. Se continuar vazio, verifique **Configurações → Sistema → Atividade**.

## Conectar o Super Agent

Esta etapa é opcional. O [DeepSeek Harness](https://www.deepseek.com/en/harness/) hospeda as sessões; o [DeepSeek Super Agent](https://github.com/deepseek-ai/dsh-superagent-prototype) acompanha o repositório e coordena quem executa as tarefas.

| Na máquina do agente | Requisito |
| --- | --- |
| JavaScript | `Node.js 22.19+` na linha 22.x ou `24+`; `pnpm` |
| Repositório | `Git 2.32+`, `gh 2.48+` e um clone local do repositório |
| Execução | `Python 3.8+` e `tmux` |
| Conta | Uma conta GitHub separada para o bot, com acesso de escrita; um provedor de modelo configurado no perfil do Harness |

1. [Baixe o Harness](https://www.deepseek.com/en/harness/), instale o comando `dsh` e [faça login com a conta do bot](agent/setup.md#2-the-bot-identity). **IAs e setup** indica o que falta na máquina.
2. Abra **Configurações → Projetos → Conectar o Super Agent**. Para a primeira instalação, informe o repositório e a pasta local, revise a proposta e confirme. **Já tem um perfil?** Use **Buscar perfis novamente** e adicione o perfil detectado. Para instalar pelo terminal, siga o [guia oficial](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/SETUP.md).
3. De uma conta autorizada, mencione o bot em uma issue pequena. Confira o ticket no painel e a resposta na issue. Veja também os [requisitos e permissões oficiais](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/docs/006-deployment.md#prerequisites).

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
