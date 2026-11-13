defmodule AgentBoard.Setup.WorkerTitles do
  @moduledoc "On-disk evidence from the same installer the owner runs on the Harness host."

  @script "scripts/agent/install-worker-titles.py"
  @states %{
    "installed" => :installed,
    "missing" => :missing,
    "needs-update" => :needs_update,
    "conflict" => :conflict
  }

  def command, do: "python3 " <> @script

  def status do
    home =
      Application.get_env(:agent_board, :worker_titles_home) || System.get_env("DSH_HOME") ||
        Path.expand("~/.dsh")

    with python when is_binary(python) <- System.find_executable("python3"),
         script = Path.join(AgentBoard.System.Git.root(), @script),
         true <- File.regular?(script),
         {output, 0} <-
           System.cmd(python, [script, "--check"],
             env: [{"DSH_HOME", home}],
             stderr_to_stdout: true
           ) do
      Map.get(@states, String.trim(output), :unknown)
    else
      _ -> :unknown
    end
  rescue
    ErlangError -> :unknown
  end
end
