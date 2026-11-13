# Set up your first board

[Português (Brasil)](primeiros-passos.md) · [Project overview](../README.md)

## Track a GitHub repository

Install `Git`, `Elixir 1.19`, `Erlang/OTP 27` and `PostgreSQL 16`. The development database is `agent_board_dev` at `127.0.0.1:5434`, with username and password `board`. If you prefer Docker, start it with:

```sh
docker run --name dsh-board-postgres -d -p 127.0.0.1:5434:5432 \
  -e POSTGRES_USER=board -e POSTGRES_PASSWORD=board -e POSTGRES_DB=agent_board_dev postgres:16
```

1. Download the board and create its local configuration:

   ```sh
   git clone https://github.com/sallaumen/dsh-superagent-superboard.git
   cd dsh-superagent-superboard
   cp .env .env.local
   ```

2. Set `GITHUB_TOKEN` in `.env.local` ([GitHub token settings](https://github.com/settings/tokens)). Give it read access to the repository you want to follow; allow issue creation if you plan to publish requests. Keep the file out of Git. Start the board:

   ```sh
   mix setup
   PORT=4002 mix phx.server
   ```

3. Visit [localhost:4002](http://127.0.0.1:4002). Choose **Settings → AI and setup → Use GitHub only**, enter the repository owner and name, and select **Track repository**. After sync, open the project from the sidebar. If it stays empty, check **Settings → System → Activity** for the last sync.

You can stop here. To publish your first request or try voice, follow the [first request walkthrough](first-request.md).

## Connect the Super Agent

[DeepSeek Harness](https://www.deepseek.com/en/harness/) hosts sessions. [DeepSeek Super Agent](https://github.com/deepseek-ai/dsh-superagent-prototype) is the package that watches a GitHub repository and coordinates workers.

| On the agent machine | Requirement |
| --- | --- |
| JavaScript | `Node.js 22.19+` on the 22.x line or `24+`; `pnpm` |
| Repository tools | `Git 2.32+`, `gh 2.48+` and a local clone of the target repository |
| Worker tools | `Python 3.8+` and `tmux` |
| Identity | A separate GitHub bot account with repository write access; a model provider configured in the Harness profile |

1. [Download Harness](https://www.deepseek.com/en/harness/), install its `dsh` command and [sign in as the bot](agent/setup.md#2-the-bot-identity). **Settings → AI and setup** shows missing tools and sign-in steps.
2. Open **Settings → Projects → Connect the Super Agent**. For a first installation, enter the repository and local folder, review what will be installed and confirm. **Already installed?** Select **Look for profiles again** and add the detected profile. For a manual installation, use the [upstream setup guide](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/SETUP.md).
3. From an authorized GitHub account, mention the bot in a small issue with a verifiable outcome. Look for its ticket in the board and its reply on the issue.

[Deployment prerequisites and permissions](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/docs/006-deployment.md#prerequisites) · [Verify the agent](agent/setup.md#5-verify-it-is-configured-and-alive) · [Add a second repository](agent/setup.md#a-second-repository-optional)
