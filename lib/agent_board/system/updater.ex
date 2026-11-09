defmodule AgentBoard.System.Updater do
  @moduledoc """
  Fast-forwards this checkout to origin/main, only when a person asks, and
  restarts the node so a changed mix.lock or config file is actually reloaded.

  Nothing here runs on a timer. The board watches agents, and an automatic
  restart would interrupt them -- which is why this is a button and not a
  cron. `pull/0` never merges or rebases: a diverged branch is an error the
  person resolves, not something the panel hides.

  A dependency or configuration change cannot be hot-reloaded: the running VM
  keeps the old modules. The node has two restart modes:

    * `AGENT_BOARD_RESTART_MODE=supervised` (the launchd/service.sh setup):
      stop and let the service manager boot the prepared code.
  The update is staged: dependencies, the new build and the assets are
  prepared in `_build/next` while the old node still serves; the boot path
  promotes that build to `_build` before starting, so the outage is the boot
  time, not the preparation.
    * anything else (a bare `mix phx.server`): start a detached shell that
      waits for this OS process to exit, refreshes dependencies and the
      schema, and boots `mix phx.server` on the same port. Its log is
      `agent-board-update-restart.log` in the system temp directory.
  """

  alias AgentBoard.System.Git

  @type result :: {:ok, String.t() | nil} | {:error, term()}

  @next_build "_build/next"
  @previous_build "_build/prev"
  @marker ".agent-board-next-build"
  @mix_timeout 180_000

  @doc """
  Records the mtimes of the files the dev code reloader watches.

  A fast-forward can change `mix.lock` or a config file while the old node
  still serves; Phoenix's reloader raises "could not compile application"
  on the next request. Restoring these mtimes right after the merge keeps
  the reloader quiet during the short preparation window; the next boot
  reads the real files.
  """
  @spec freeze_config_files(Path.t()) :: [{String.t(), tuple()}]
  def freeze_config_files(root \\ Git.root()) do
    for file <- config_files(root),
        {:ok, %File.Stat{mtime: mtime}} <- [File.stat(Path.join(root, file))],
        do: {file, mtime}
  end

  @spec restore_config_files([{String.t(), tuple()}], Path.t()) :: :ok
  def restore_config_files(times, root \\ Git.root()) do
    Enum.each(times, fn {file, mtime} -> File.touch(Path.join(root, file), mtime) end)
    :ok
  end

  defp config_files(root) do
    configs =
      root
      |> Path.join("config/*.exs")
      |> Path.wildcard()
      |> Enum.map(&Path.relative_to(&1, root))

    ["mix.exs", "mix.lock" | configs]
  end

  @doc "Fetches origin/main and fast-forwards HEAD to it."
  @spec pull() :: result()
  def pull do
    with :ok <- Git.fetch(),
         {:ok, _output} <- fast_forward() do
      Git.head()
    end
  end

  @doc """
  Fetches the dependencies the new checkout names **before** the node stops.

  A dependency change is the slow part of a restart (`mix deps.get` can take
  tens of seconds). Running it while the old node still answers keeps the
  board up if the network or Hex fails; the caller only stops after `:ok`.
  Migrations stay in the boot path: a schema change is not prepared against a
  running old node.
  """
  @spec prepare() :: :ok | {:error, term()}
  def prepare do
    case run_mix(["deps.get"]) do
      :ok -> :ok
      error -> error
    end
  end

  @doc """
  Compiles the new checkout and its assets into `_build/next`, without
  touching the build the running node uses. The old node keeps answering
  while this runs; the build is promoted to `_build` only at the next boot.
  """
  @spec prepare_build() :: :ok | {:error, term()}
  def prepare_build do
    env = [{"MIX_BUILD_PATH", @next_build}, {"MIX_ENV", mix_env()}]

    with :ok <- run_mix(["deps.get"]) do
      run_mix(["compile"], env: env, timeout: 600_000)
    end
  end

  @doc "Builds the assets into priv/static while the old node still serves them."
  @spec prepare_assets() :: :ok | {:error, term()}
  def prepare_assets do
    env = [{"MIX_BUILD_PATH", @next_build}, {"MIX_ENV", mix_env()}]
    run_mix(["assets.build"], env: env, timeout: 600_000)
  end

  @doc """
  Applies the pending migrations while the old node still serves.

  Runs inside the staged build so the mix task never compiles into the
  running node's `_build` (that would hand the code reloader new modules
  before the stop).
  """
  @spec migrate() :: :ok | {:error, term()}
  def migrate do
    run_mix(["ecto.migrate"],
      env: [{"MIX_BUILD_PATH", @next_build}, {"MIX_ENV", mix_env()}]
    )
  end

  @doc "Writes the marker the boot path promotes to `_build` before starting."
  # The path is this checkout's root, never request input.
  @spec mark_ready(Path.t()) :: :ok
  def mark_ready(root \\ Git.root()) do
    File.mkdir_p!(root)
    File.write!(Path.join(root, @marker), @next_build)
    :ok
  end

  @doc "The prepared build path, or nil when nothing is staged."
  @spec pending_build(Path.t()) :: String.t() | nil
  def pending_build(root \\ Git.root()) do
    case File.read(Path.join(root, @marker)) do
      {:ok, build} -> String.trim(build)
      {:error, _} -> nil
    end
  end

  @doc "Drops the staged marker; the next build stays on disk for a retry."
  @spec clear_marker(Path.t()) :: :ok
  def clear_marker(root \\ Git.root()) do
    File.rm(Path.join(root, @marker))
    :ok
  end

  defp run_mix(args, opts \\ []) do
    env = Keyword.get(opts, :env, [])
    timeout = Keyword.get(opts, :timeout, @mix_timeout)

    task =
      Task.async(fn ->
        System.cmd("mix", args,
          cd: Git.root(),
          stderr_to_stdout: true,
          env: [{"MIX_ENV", mix_env()} | env]
        )
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {_output, 0}} -> :ok
      {:ok, {output, status}} -> {:error, {:mix, status, String.slice(output, -2_000, 2_000)}}
      nil -> {:error, :timeout}
    end
  end

  defp mix_env, do: System.get_env("MIX_ENV", "dev")

  # The boot promotion, in shell so launchd's service.sh and the detached
  # restart script share it without starting a second mix process.
  defp promote_lines do
    """
    if [ -f #{@marker} ]; then
      next_build="$(cat #{@marker})"
      if [ -d "$next_build" ]; then
        rm -rf #{@previous_build}
        [ -d _build ] && mv _build #{@previous_build}
        mv "$next_build" _build
        rm -f #{@marker}
      fi
    fi
    """
  end

  @doc false
  def promote_snippet, do: promote_lines()

  @doc """
  Schedules the boot of the updated code, or returns `:ok` when a service
  manager owns the process and will do it after this VM exits.
  """
  @spec restart() :: :ok
  def restart do
    case System.get_env("AGENT_BOARD_RESTART_MODE") do
      "supervised" -> :ok
      _ -> self_restart()
    end
  end

  defp self_restart do
    root = Git.root()
    log = Path.join(System.tmp_dir!(), "agent-board-update-restart.log")
    script = restart_script(root, System.pid())

    command = "nohup sh -c #{sh_quote(script)} > #{sh_quote(log)} 2>&1 < /dev/null &"

    case System.cmd("sh", ["-c", command], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> raise "could not schedule the restart (#{status}): #{output}"
    end
  end

  @doc false
  # Public so the script can be asserted without spawning a process.
  def restart_script(root, os_pid) do
    """
    #!/bin/sh
    # Generated by AgentBoard.System.Updater. Wait for the old VM to release
    # the port, then promote the staged build and boot the updated code.
    while kill -0 #{os_pid} 2>/dev/null; do sleep 0.2; done
    cd #{sh_quote(root)} || exit 1
    #{promote_lines()}mix deps.get || exit 1
    mix ecto.migrate || exit 1
    exec mix phx.server
    """
  end

  defp fast_forward do
    case Git.run(["merge", "--ff-only", "origin/main"]) do
      {:ok, output} -> {:ok, output}
      error -> error
    end
  end

  defp sh_quote(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
end
