# Set up your first board

[Português (Brasil)](primeiros-passos.md) · [Project overview](../README.md)

## Track a GitHub repository

Install [Git](https://git-scm.com/downloads) and [Elixir with Erlang/OTP](https://elixir-lang.org/install.html). Run `git --version` and `elixir --version`: the board is tested with `Elixir 1.19` and `Erlang/OTP 27`. For the database choose **one**: [PostgreSQL 16](https://www.postgresql.org/download/) or [Docker](https://docs.docker.com/get-started/get-docker/) with the command below. The development database is `agent_board_dev` at `127.0.0.1:5434`, with username and password `board`. If you prefer Docker, start it with:

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

2. Set `GITHUB_TOKEN` in `.env.local` ([GitHub token settings](https://github.com/settings/tokens)). For a fine-grained token, select the repository owner and repository. Grant read access to contents, issues, pull requests and checks for tracking; use **Issues: read and write** to publish requests. Your personal token is for the board, not the agent. Keep the file out of Git. Start the board (accept the Hex or Rebar installation prompt if Mix asks):

   ```sh
   mix setup
   PORT=4002 mix phx.server
   ```

3. A fresh board has **no projects**. Visit [localhost:4002](http://127.0.0.1:4002). Choose **Settings → AI and setup → Use GitHub only**, enter the repository owner and name, and select **Track repository**. Use separate fields: for `octocat/Hello-World`, enter `octocat` as the owner and `Hello-World` as the name. Open the project from the sidebar. The scheduled GitHub sync runs about every five minutes; seeing **No agent** on a tracked project is expected. If it stays empty, check **Settings → System → Activity** for the last sync.

You can stop here. To publish your first request or try voice, follow the [first request walkthrough](first-request.md).

## Connect the Super Agent

[DeepSeek Harness](https://www.deepseek.com/en/harness/) hosts sessions. [DeepSeek Super Agent](https://github.com/deepseek-ai/dsh-superagent-prototype) is the package that watches a GitHub repository and coordinates workers.

| On the agent machine | Requirement |
| --- | --- |
| JavaScript | `Node.js 22.19+` on the 22.x line or `24+`; `pnpm` |
| Repository tools | `Git 2.32+`, `gh 2.48+` and a local clone of the target repository |
| Worker tools | `Python 3.8+` and `tmux` |
| Identity | A separate GitHub bot account with repository write access; a model provider configured in the Harness profile |

1. Install the [Harness CLI](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/docs/006-deployment.md#install): `npm install -g @deepseek-ai/dsh@0.2.1-rc.3`. Check with `dsh --version`. On Linux, use Debian with `procps`; the Alpine run did not complete.
2. For the default DeepSeek API provider, set `DEEPSEEK_API_KEY` in the board’s `.env.local` and restart the board. For another provider, configure it in [Harness](https://www.deepseek.com/en/harness/).
3. [Sign in as the bot](agent/setup.md#2-the-bot-identity) and verify its GitHub login. Leave profile creation to the board.

Open **Settings → Projects → Connect the Super Agent**, then choose the path that matches your machine:

| What you have | Next step |
| --- | --- |
| An agent already watching this repo | Select **Look for profiles again**. Choose the detected profile and confirm **Add to the board**. There is no need to create another agent. |
| No agent yet | Clone the **target project**, enter its owner, name and the folder containing its `.git`, then choose the worker limit. Review and confirm the first installation. The bot needs write access; grant it in the target repo or let the board grant it with a token that can manage collaborators. |

For a manual installation, use the [upstream setup guide](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/SETUP.md).

**Check one real task.** From an authorized account, open a small issue and mention the actual bot login. For a game repo, try “@your-bot Document one existing game control in the README and open a PR.” Look for the bot’s reply on the issue, then the ticket and linked PR in the board. Connecting the profile by itself does not submit a task.

[Deployment prerequisites and permissions](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/docs/006-deployment.md#prerequisites) · [Verify the agent](agent/setup.md#5-verify-it-is-configured-and-alive) · [Add a second repository](agent/setup.md#a-second-repository-optional)
