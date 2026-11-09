defmodule AgentBoard.RoutingProjectsTest do
  @moduledoc "The router's DeepSeek repositories come from Projects, not a setting."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Settings, Superagents}
  alias AgentBoard.Routing.Signals

  test "a superagent's repository is a repository the router can suggest" do
    {:ok, repo} = Board.add_repository("fixture", "routing-project")

    {:ok, _superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-routing-project",
        port: 3410,
        state_dir: "/tmp/superagent-routing-project"
      })

    # The old setting is still readable, but it is no longer the source.
    :ok = Settings.put("dsh_repositories", "fixture/ignored")

    signals = Signals.read(fn -> {:error, :unreachable} end, fn -> %{} end)

    assert "fixture/routing-project" in signals["dsh"].repositories
    refute "fixture/ignored" in signals["dsh"].repositories
  end
end
