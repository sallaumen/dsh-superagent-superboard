defmodule AgentBoard.Superagents.AlpineRuntime do
  @moduledoc """
  Check the installed Harness on Alpine before first provisioning. Loading its
  native subprocess library can abort Node itself; never do it in the service
  that will own the profile. No profile, repository or credentials are needed.
  """
  use Gettext, backend: AgentBoardWeb.Gettext

  def check do
    if File.regular?("/etc/alpine-release"), do: probe(System.find_executable("dsh")), else: :ok
  end

  @doc false
  def probe(nil), do: {:error, :dsh_missing}

  def probe(dsh) do
    script = Application.app_dir(:agent_board, "priv/agent/check-alpine-harness.cjs")

    case System.cmd("/usr/bin/env", ["node", script, dsh], stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {_output, 42} ->
        {:error,
         {:setup,
          gettext(
            "The agent manager cannot recognize this Node process. Use Node 22 as described in the Alpine installation guide, then try again."
          )}}

      {_output, _code} ->
        {:error,
         {:setup,
          gettext(
            "The Harness could not load its native runtime. Follow the Alpine installation guide for the compatible Koffi dependency, then try again."
          )}}
    end
  end
end
