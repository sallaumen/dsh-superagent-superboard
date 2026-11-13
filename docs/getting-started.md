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

1. [Download Harness](https://www.deepseek.com/en/harness/), install its `dsh` command and configure its model provider. From the board machine, run `dsh --version`, then [sign in as the bot](agent/setup.md#2-the-bot-identity). **Settings → AI and setup** shows missing tools and sign-in steps.
2. Open **Settings → Projects → Connect the Super Agent**. **Already have an agent for this repository?** Select **Look for profiles again**, find its profile under the detected agents and confirm **Add to the board**. This connects the existing agent instead of creating a second one. **First agent on this machine?** Clone the *target project* locally (not the board or Harness). Enter the same owner and repo, the path containing its `.git`, and a worker limit. Review the installation and confirm. The bot needs write access: grant it in the target repository beforehand, or let the board grant it if your token can manage collaborators. For a manual installation, use the [upstream setup guide](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/SETUP.md).
3. From an authorized GitHub account, mention the bot in a small issue with a verifiable outcome. For example: `@your-bot Document one existing game control in the README and open a PR.` Use the actual bot login. Check for its reply or workpad on the issue, then for the ticket and linked PR in the board. Adding a profile alone does not submit a task.

[Deployment prerequisites and permissions](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/docs/006-deployment.md#prerequisites) · [Verify the agent](agent/setup.md#5-verify-it-is-configured-and-alive) · [Add a second repository](agent/setup.md#a-second-repository-optional)
