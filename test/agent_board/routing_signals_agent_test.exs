defmodule AgentBoard.RoutingSignalsAgentTest do
  @moduledoc "The router reads the agent that serves the repository, not the primary's."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Board, Orchestrator, Repo, Routing.Signals}
  alias AgentBoard.Superagents.Superagent

  @stub AgentBoard.RoutingSignalsAgentTest.Stub

  setup do
    previous_api = Application.get_env(:agent_board, :orchestrator_api)
    previous_client = Application.get_env(:agent_board, :orchestrator_client)
    Application.put_env(:agent_board, :orchestrator_api, "http://127.0.0.1:1/orchestrator/api")

    Application.put_env(:agent_board, :orchestrator_client, fn ->
      Req.merge(Orchestrator.build(), plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn ->
      restore(:orchestrator_api, previous_api)
      restore(:orchestrator_client, previous_client)
    end)

    # The primary (port 1) is paused; o_colmex's own agent (3083) is ready.
    Req.Test.stub(@stub, fn conn ->
      {repository, paused} =
        if conn.port == 3083, do: {"fixture/colmex", false}, else: {"fixture/arena", true}

      Req.Test.json(conn, %{
        "paused" => paused,
        "load" => %{"running" => 0, "queued" => 0, "maxWorkers" => 3},
        "setup" => %{"accounts" => %{"repository" => repository}}
      })
    end)

    {:ok, arena} = Board.add_repository("fixture", "arena")
    {:ok, colmex} = Board.add_repository("fixture", "colmex")

    %Superagent{}
    |> Superagent.changeset(%{
      repository_id: colmex.id,
      profile: "superagent-colmex",
      port: 3083,
      state_dir: "/tmp/superagent-colmex"
    })
    |> Repo.insert!()

    %{arena: arena, colmex: colmex}
  end

  defp restore(key, nil), do: Application.delete_env(:agent_board, key)
  defp restore(key, value), do: Application.put_env(:agent_board, key, value)

  test "a repository with its own agent is routed by that agent's state", %{
    arena: arena,
    colmex: colmex
  } do
    assert %{"dsh" => %{state: :ready}} = Signals.read_for(colmex, fn -> %{} end)
    assert %{"dsh" => %{state: :paused}} = Signals.read_for(arena, fn -> %{} end)
  end
end
