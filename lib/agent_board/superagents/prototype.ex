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
        with :ok <- step(run, "git", ["clone", "--depth", "1", @repository, target], []),
             :ok <- step(run, "pnpm", ["install"], cd: target),
             :ok <- step(run, "pnpm", ["build"], cd: target) do
          Settings.put(@setting, target)
        end
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
