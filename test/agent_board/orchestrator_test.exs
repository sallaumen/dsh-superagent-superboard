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

  test "the dispatch state names the watched repository and the pause" do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{
        "load" => %{"running" => 0, "queued" => 0, "maxWorkers" => 3},
        "paused" => true,
        "setup" => %{"accounts" => %{"repository" => "sallaumen/arena-rogue"}}
      })
    end)

    assert Orchestrator.dispatch_state() ==
             {:ok,
              %{
                repository: "sallaumen/arena-rogue",
                paused: true,
                load: %{running: 0, queued: 0, max_workers: 3}
              }}
  end

  test "a state without the repository leaves it unknown" do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"load" => %{"running" => 1, "queued" => 0, "maxWorkers" => 2}})
    end)

    assert {:ok, %{repository: nil, paused: false}} = Orchestrator.dispatch_state()
  end

  describe "set_max_workers/2" do
    @executor %{
      "model" => %{"provider" => "deepseek-account", "model" => "deepseek-flash"},
      "maxWorkers" => 3,
      "directory" => "/work",
      "prepare" => "git worktree add",
      "blockedCommands" => []
    }

    test "saves the whole executor block with the new ceiling at the revision it read" do
      test_pid = self()

      Req.Test.stub(@stub, fn
        %{method: "GET", request_path: "/orchestrator/api/settings"} = conn ->
          Req.Test.json(conn, %{
            "blocks" => %{"executor" => %{"value" => @executor, "revision" => 7}}
          })

        %{method: "PUT", request_path: "/orchestrator/api/settings/executor"} = conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test_pid, {:put, Jason.decode!(body)})
          Req.Test.json(conn, %{"saved" => true, "revision" => 8, "restarting" => false})
      end)

      assert Orchestrator.set_max_workers(Orchestrator.client(), 5) == {:ok, 5}
      assert_receive {:put, %{"revision" => 7, "value" => value}}
      assert value == Map.put(@executor, "maxWorkers", 5)
    end

    test "a save that would restart the runner is reported" do
      Req.Test.stub(@stub, fn
        %{method: "GET"} = conn ->
          Req.Test.json(conn, %{
            "blocks" => %{"executor" => %{"value" => @executor, "revision" => 7}}
          })

        %{method: "PUT"} = conn ->
          Req.Test.json(conn, %{"saved" => true, "revision" => 8, "restarting" => true})
      end)

      assert Orchestrator.set_max_workers(Orchestrator.client(), 2) == {:ok, 2, :restarting}
    end

    test "a settings change in between is a conflict, not an overwrite" do
      Req.Test.stub(@stub, fn
        %{method: "GET"} = conn ->
          Req.Test.json(conn, %{
            "blocks" => %{"executor" => %{"value" => @executor, "revision" => 7}}
          })

        %{method: "PUT"} = conn ->
          conn |> Plug.Conn.put_status(409) |> Req.Test.json(%{"error" => "Settings changed."})
      end)

      assert Orchestrator.set_max_workers(Orchestrator.client(), 4) == {:error, :conflict}
    end

    test "a ceiling outside the runner's range is refused before the network" do
      Req.Test.stub(@stub, fn _conn -> flunk("no request expected") end)

      assert Orchestrator.set_max_workers(Orchestrator.client(), 0) == {:error, :out_of_range}
      assert Orchestrator.set_max_workers(Orchestrator.client(), 17) == {:error, :out_of_range}
      assert Orchestrator.set_max_workers(nil, 3) == {:error, :not_configured}
    end
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
