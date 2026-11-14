defmodule AgentBoard.Superagents.Prototype do
  @moduledoc """
  Where the agent's code is on this machine: the checkout of
  `dsh-superagent`, whose `scripts/dsh-superagent` starts, stops and checks
  every agent, and which each agent's profile loads as a plugin.

  The board finds it, in order: the `:dsh_superagent_home` setting of the
  application (tests), the `DSH_SUPERAGENT_HOME` variable, the folder the
  board itself installed (`settings`, `dsh_superagent_home`), and last the
  place it has always been on the owner's machine. A board that never
  installed it reads no row and finds what it found before.

  `install/0` is for a machine that does not have it: the public repository
  cloned under the dsh home and built, as the prototype's own install says,
  then remembered. It runs only as part of installing a first agent
  (`DshProvisioner`), after the owner's confirmation.
  """

  alias AgentBoard.{Settings, Superagents}

  @legacy "~/Documents/deepseek-harness/default-workspace/dsh-superagent-prototype"
  @repository "https://github.com/deepseek-ai/dsh-superagent-prototype.git"
  # Upstream source revision against which the bundled extension is tested.
  @revision "8c32a9dc5d72c033816c6a8110b37f40cf94fba4"
  @setting "dsh_superagent_home"

  @doc "The checkout's folder."
  @spec home() :: String.t()
  def home do
    Application.get_env(:agent_board, :dsh_superagent_home) ||
      System.get_env("DSH_SUPERAGENT_HOME") || Settings.get(@setting) || legacy()
  end

  # `:dsh_superagent_legacy_home` stands in for the owner's folder in tests.
  defp legacy,
    do: Application.get_env(:agent_board, :dsh_superagent_legacy_home) || Path.expand(@legacy)

  @doc "The script that starts, stops and checks an agent."
  @spec manager() :: String.t()
  def manager, do: Path.join(home(), "scripts/dsh-superagent")

  @doc "Where the board puts a checkout it installs: beside the profiles."
  @spec target() :: String.t()
  def target, do: Path.join(Path.dirname(Superagents.profiles_root()), "dsh-superagent")

  @doc """
  Clones and builds the checkout when this machine has none, and remembers
  where. `run` takes a tool with its arguments and `System.cmd/3`'s options.
  A folder already at the target that is not a working checkout is left alone
  and reported.
  """
  @spec install(([String.t()], keyword() -> {String.t(), integer()})) ::
          :ok | {:error, term()}
  def install(run) do
    target = target()

    cond do
      File.exists?(manager()) ->
        :ok

      File.exists?(Path.join(target, "scripts/dsh-superagent")) ->
        Settings.put(@setting, target)

      File.exists?(target) ->
        {:error, {:prototype_in_the_way, target}}

      true ->
        install_new(run, target)
    end
  end

  defp install_new(run, target) do
    # Never let a failed build look like an installed manager on the next attempt.
    stage = target <> ".installing"
    patch = Application.app_dir(:agent_board, "priv/agent/duplicate-issue-notice.patch")

    branch_patch = Path.join(Path.dirname(patch), "assignment-branch.patch")
    publication_patch = Path.join(Path.dirname(patch), "managed-publication.patch")
    container_patch = Path.join(Path.dirname(patch), "container-worker.patch")
    cleanup_patch = Path.join(Path.dirname(patch), "container-report-cleanup.patch")
    container_helper = Path.join(Path.dirname(patch), "container_worker.py")
    helper = Path.join(Path.dirname(patch), "superboard-branch.py")

    # Git creates its destination. Leave an interrupted checkout for inspection.
    with {:error, :enoent} <- File.lstat(stage),
         :ok <- step(run, "git", ["clone", "--no-checkout", @repository, stage], []),
         :ok <- step(run, "git", ["checkout", "--detach", @revision], cd: stage),
         :ok <- step(run, "git", ["apply", patch], cd: stage),
         :ok <- step(run, "git", ["apply", branch_patch], cd: stage),
         :ok <- step(run, "git", ["apply", publication_patch], cd: stage),
         :ok <- step(run, "git", ["apply", container_patch], cd: stage),
         :ok <- step(run, "git", ["apply", cleanup_patch], cd: stage),
         :ok <- step(run, "cp", [container_helper, "scripts/container_worker.py"], cd: stage),
         :ok <- step(run, "cp", [helper, "scripts/superboard-branch.py"], cd: stage),
         :ok <- step(run, "pnpm", ["install", "--frozen-lockfile"], cd: stage),
         :ok <- step(run, "pnpm", ["build"], cd: stage),
         :ok <- File.rename(stage, target) do
      Settings.put(@setting, target)
    else
      {:ok, %File.Stat{}} -> {:error, {:prototype_in_the_way, stage}}
      error -> error
    end
  end

  defp step(run, tool, args, opts) do
    case run.([tool | args], [stderr_to_stdout: true] ++ opts) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, {:command, tool, String.slice(output, -500, 500)}}
    end
  rescue
    exception -> {:error, {:command, tool, Exception.message(exception)}}
  end
end
