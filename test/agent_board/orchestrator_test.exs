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

  describe "retry/2" do
    test "posts the ticket's retry with the required header" do
      test_pid = self()

      Req.Test.stub(@stub, fn conn ->
        send(
          test_pid,
          {:retry, conn.method, conn.request_path,
           Plug.Conn.get_req_header(conn, "x-orchestrator-request")}
        )

        Req.Test.json(conn, %{"retried" => true})
      end)

      assert Orchestrator.retry(Orchestrator.client(), "abc123") == {:ok, :retried}
      assert_receive {:retry, "POST", "/orchestrator/api/tickets/abc123/retry", ["1"]}
    end

    test "a refusal carries the runner's code" do
      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"error" => "no", "code" => "notRetryable"})
      end)

      assert Orchestrator.retry(Orchestrator.client(), "abc") ==
               {:error, {:refused, "notRetryable"}}
    end

    test "an unknown ticket, a 5xx, a refused connection and a timeout are reasons" do
      Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 404, "{}") end)
      assert Orchestrator.retry(Orchestrator.client(), "abc") == {:error, :unknown_ticket}

      Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
      assert Orchestrator.retry(Orchestrator.client(), "abc") == {:error, {:http, 500}}

      Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
      assert Orchestrator.retry(Orchestrator.client(), "abc") == {:error, :unreachable}

      Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :timeout) end)
      assert Orchestrator.retry(Orchestrator.client(), "abc") == {:error, :timeout}
    end

    test "nothing is sent when the API is off" do
      assert Orchestrator.retry(nil, "abc") == {:error, :not_configured}
    end
  end

  test "the test environment switches the API off" do
    Application.put_env(:agent_board, :orchestrator_api, false)
    assert Orchestrator.load(nil) == {:error, :not_configured}
    assert Orchestrator.build() == nil
  end
end
