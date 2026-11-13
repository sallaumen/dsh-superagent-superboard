defmodule AgentBoard.Superagents.Bot do
  @moduledoc """
  The agent's own GitHub identity on this machine, apart from the owner's:
  a `gh` configuration folder of its own (`~/.config/gh-agent`) and the
  wrapper that runs `gh` with it (`~/.local/bin/gh-agent`), as the
  prototype's deployment guide sets them up. The board reads who that
  sign-in is; it never signs in, and never sees a password or a token.
  """

  @timeout_ms 8_000

  @doc "The folder of the bot's `gh` sign-in."
  def config,
    do: Application.get_env(:agent_board, :agent_gh_config, Path.expand("~/.config/gh-agent"))

  @doc "The wrapper the agent runs as its GitHub CLI."
  def cli,
    do: Application.get_env(:agent_board, :agent_gh_cli, Path.expand("~/.local/bin/gh-agent"))

  @doc "Whether a sign-in for the bot is on this machine. No network."
  def signed_in?, do: File.regular?(Path.join(config(), "hosts.yml"))

  @doc """
  Who the bot's sign-in is, asked of GitHub the way dsh-superagent asks. The
  login is a public name, and nothing else of the answer is kept.
  """
  @spec login() :: {:ok, String.t()} | {:error, :missing | :logged_out | :timeout}
  def login do
    with true <- signed_in?() || {:error, :missing},
         gh when is_binary(gh) <- System.find_executable("gh") || {:error, :missing} do
      # The board's own token would win over the bot's sign-in.
      env = [{"GH_CONFIG_DIR", config()}, {"GITHUB_TOKEN", nil}, {"GH_TOKEN", nil}]

      task =
        Task.async(fn ->
          System.cmd("/usr/bin/env", [gh, "api", "user", "--jq", ".login"],
            env: env,
            stderr_to_stdout: true
          )
        end)

      case Task.yield(task, @timeout_ms) || Task.shutdown(task) do
        {:ok, {output, 0}} -> named(String.trim(output))
        {:ok, {_output, _status}} -> {:error, :logged_out}
        nil -> {:error, :timeout}
      end
    end
  end

  defp named(""), do: {:error, :logged_out}
  defp named(login), do: {:ok, login}
end
