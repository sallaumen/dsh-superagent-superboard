defmodule AgentBoard.OrchestratorTest do
  @moduledoc "The runner's load is read, never guessed: a dead API is a reason."
  use ExUnit.Case, async: false

  alias AgentBoard.Orchestrator

  @stub AgentBoard.OrchestratorTest.Stub

  setup do
    previous = Application.get_env(:agent_board, :orchestrator_client)
    previous_api = Application.get_env(:agent_board, :orchestrator_api)
    Application.put_env(:agent_board, :orchestrator_client, fn -> stub_client() end)

    on_exit(fn ->
      restore(:orchestrator_client, previous)
      restore(:orchestrator_api, previous_api)
    end)

    :ok
  end

  # The real client (headers, timeouts) with the network replaced by the stub.
  defp stub_client do
    Application.put_env(:agent_board, :orchestrator_api, "http://127.0.0.1:1/orchestrator/api")
    Req.merge(Orchestrator.build(), plug: {Req.Test, @stub})
  end

  defp restore(key, nil), do: Application.delete_env(:agent_board, key)
  defp restore(key, value), do: Application.put_env(:agent_board, key, value)

  test "reads running, queued and the ceiling, and sends the required header" do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      send(test_pid, {:header, Plug.Conn.get_req_header(conn, "x-orchestrator-request")})
      Req.Test.json(conn, %{"load" => %{"running" => 1, "queued" => 2, "maxWorkers" => 3}})
    end)

    assert Orchestrator.load() == {:ok, %{running: 1, queued: 2, max_workers: 3}}
    assert_receive {:header, ["1"]}
  end

  test "a body without load is malformed" do
    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"health" => %{}}) end)
    assert Orchestrator.load() == {:error, :malformed}
  end

  test "a non-200 is the status" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 503, "down") end)
    assert Orchestrator.load() == {:error, {:http, 503}}
  end

  test "a transport failure is unreachable, not a raise" do
    Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
    assert Orchestrator.load() == {:error, :unreachable}
  end

  test "the test environment switches the API off" do
    Application.put_env(:agent_board, :orchestrator_api, false)
    assert Orchestrator.load(nil) == {:error, :not_configured}
    assert Orchestrator.build() == nil
  end
end
