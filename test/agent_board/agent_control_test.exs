defmodule AgentBoard.AgentControlTest do
  @moduledoc "The owner's two asks of the agent: a retry and a restart, each with its sentence."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{AgentControl, Board, Orchestrator, Repo}
  alias AgentBoard.Board.Event
  alias AgentBoard.Superagents.Superagent

  @stub AgentBoard.AgentControlTest.Stub

  setup do
    previous_api = Application.get_env(:agent_board, :orchestrator_api)
    Application.put_env(:agent_board, :orchestrator_api, "http://127.0.0.1:1/orchestrator/api")
    client = Req.merge(Orchestrator.build(), plug: {Req.Test, @stub})

    on_exit(fn ->
      if is_nil(previous_api),
        do: Application.delete_env(:agent_board, :orchestrator_api),
        else: Application.put_env(:agent_board, :orchestrator_api, previous_api)
    end)

    {:ok, repo} = Board.add_repository("fixture", "agent-control")
    %{client: client, repo: repo}
  end

  test "a retry asked by the owner is sent and recorded", %{client: client, repo: repo} do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/orchestrator/api/tickets/t9/retry"
      Req.Test.json(conn, %{"retried" => true})
    end)

    assert {:ok, text} =
             AgentControl.retry("t9", client: client, repository_id: repo.id, number: 9)

    assert text =~ "Nova tentativa pedida"

    assert [%Event{kind: "agent_retry_manual", subject: "Retry requested by you on #9"}] =
             Repo.all(from e in Event, where: e.repository_id == ^repo.id)
  end

  test "a refusal is a sentence, and it is recorded too", %{client: client, repo: repo} do
    Req.Test.stub(@stub, fn conn ->
      conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"code" => "notRetryable"})
    end)

    assert {:error, text} =
             AgentControl.retry("t9", client: client, repository_id: repo.id, number: 9)

    assert text =~ "O agente recusou: só tenta de novo"

    assert [%Event{subject: subject}] =
             Repo.all(from e in Event, where: e.repository_id == ^repo.id)

    # the stored subject is English whoever asked; the answer above is the asker's
    assert subject =~ "Retry requested by you on #9 was not accepted: The agent refused"
  end

  test "an agent that does not answer says to restart it", %{client: client} do
    Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

    assert {:error, "O agente não respondeu. Religue o agente e tente de novo."} =
             AgentControl.retry("t9", client: client)
  end

  describe "the agent of the ticket's repository" do
    setup do
      previous = Application.get_env(:agent_board, :orchestrator_client)

      Application.put_env(:agent_board, :orchestrator_client, fn ->
        Req.merge(Orchestrator.build(), plug: {Req.Test, @stub})
      end)

      on_exit(fn ->
        if is_nil(previous),
          do: Application.delete_env(:agent_board, :orchestrator_client),
          else: Application.put_env(:agent_board, :orchestrator_client, previous)
      end)

      test = self()

      Req.Test.stub(@stub, fn conn ->
        send(test, {:request, conn.method, conn.port, conn.request_path})
        Req.Test.json(conn, %{"retried" => true})
      end)
    end

    test "a repository with its own superagent is asked on that port", %{repo: repo} do
      {:ok, _superagent} =
        %Superagent{}
        |> Superagent.changeset(%{
          repository_id: repo.id,
          profile: "superagent-colmex",
          port: 3083,
          state_dir: "/tmp/superagent-colmex"
        })
        |> Repo.insert()

      assert {:ok, _text} = AgentControl.retry("t9", repository_id: repo.id, number: 9)
      assert_receive {:request, "POST", 3083, "/orchestrator/api/tickets/t9/retry"}
    end

    test "a repository without one is asked on the primary", %{repo: repo} do
      assert {:ok, _text} = AgentControl.retry("t9", repository_id: repo.id, number: 9)
      assert_receive {:request, "POST", 1, "/orchestrator/api/tickets/t9/retry"}
    end
  end

  test "no ticket, no request" do
    assert {:error, _text} = AgentControl.retry(nil)
  end

  test "a restart says how it went, from the manager's exit status" do
    assert AgentControl.start_agent(starter: fn -> {"started", 0} end) ==
             {:ok, "O agente está de pé."}

    assert AgentControl.start_agent(
             starter: fn -> {"Log: x\nBoth dsh and tmux must be on PATH.\n", 1} end
           ) ==
             {:error, "O agente não subiu (saída 1): Both dsh and tmux must be on PATH."}
  end

  test "a restart that hangs is cut at the timeout and said so" do
    Application.put_env(:agent_board, :agent_start_timeout_ms, 50)
    on_exit(fn -> Application.delete_env(:agent_board, :agent_start_timeout_ms) end)

    assert {:error, text} = AgentControl.start_agent(starter: fn -> Process.sleep(1_000) end)
    assert text =~ "não respondeu em 0 s"
  end
end
