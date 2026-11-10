defmodule AgentBoardWeb.WorkerLimitTest do
  @moduledoc "The executor's ceiling is changed where it is shown, in the Paralelismo tile."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Orchestrator, Repo}
  alias AgentBoard.Board.Task
  alias AgentBoard.Superagents.Superagent
  alias AgentBoardWeb.BoardLive

  @stub AgentBoardWeb.WorkerLimitTest.Stub

  @executor %{
    "model" => %{"provider" => "deepseek-account", "model" => "deepseek-flash"},
    "maxWorkers" => 3,
    "directory" => "/work",
    "prepare" => "git worktree add",
    "blockedCommands" => []
  }

  setup do
    previous_client = Application.get_env(:agent_board, :orchestrator_client)
    previous_api = Application.get_env(:agent_board, :orchestrator_api)
    {:ok, runner} = Agent.start_link(fn -> %{max: 3, revision: 7, puts: []} end)

    Req.Test.set_req_test_to_shared(%{})
    Application.put_env(:agent_board, :orchestrator_api, "http://127.0.0.1:1/orchestrator/api")

    Application.put_env(:agent_board, :orchestrator_client, fn ->
      Req.merge(Orchestrator.build(), plug: {Req.Test, @stub})
    end)

    Req.Test.stub(@stub, &runner(&1, runner))

    on_exit(fn ->
      Req.Test.set_req_test_to_private(%{})
      restore(:orchestrator_client, previous_client)
      restore(:orchestrator_api, previous_api)
    end)

    # The strip shows only on a board with tasks.
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    insert_task(repo)

    %{runner: runner, repo: repo}
  end

  defp insert_task(repo) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 1,
      title: "t",
      state: "queued"
    })
    |> Repo.insert!()
  end

  defp own_agent(repo, port) do
    %Superagent{}
    |> Superagent.changeset(%{
      repository_id: repo.id,
      profile: "superagent-colmex",
      port: port,
      state_dir: "/tmp/superagent-colmex"
    })
    |> Repo.insert!()
  end

  test "the ceiling and the load use the repository's agent, with the primary down", %{
    conn: conn,
    repo: repo,
    runner: runner
  } do
    own_agent(repo, 3083)
    test = self()

    Req.Test.stub(@stub, fn
      %{port: 3083} = conn ->
        send(test, {:agent, conn.method, conn.request_path})
        runner(conn, runner)

      conn ->
        Req.Test.transport_error(conn, :econnrefused)
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    render_async(view, 2_000)

    assert_receive {:agent, "GET", "/orchestrator/api/state"}
    assert has_element?(view, "#flow-load [data-key='load-max']", "3")

    view |> element("#flow-load button[aria-label='Mais um agente']") |> render_click()

    assert_receive {:agent, "PUT", "/orchestrator/api/settings/executor"}
    assert [%{"value" => %{"maxWorkers" => 4}}] = Agent.get(runner, & &1.puts)
  end

  test "the repository's agent down reads as unknown, with the primary up", %{
    conn: conn,
    repo: repo,
    runner: runner
  } do
    own_agent(repo, 3083)

    Req.Test.stub(@stub, fn
      %{port: 3083} = conn -> Req.Test.transport_error(conn, :econnrefused)
      conn -> runner(conn, runner)
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    render_async(view, 2_000)

    assert has_element?(view, "#flow-load [data-key='load-max']", "?")
  end

  test "switching repository does not show the previous repository's answer", %{
    conn: conn,
    repo: repo,
    runner: runner
  } do
    own_agent(repo, 3083)
    {:ok, other} = Board.add_repository("sallaumen", "o_colmex")
    insert_task(other)
    test = self()

    # The other repository's agent (the primary) answers when the test says.
    Req.Test.stub(@stub, fn
      %{port: 3083} = conn ->
        runner(conn, runner)

      conn ->
        send(test, {:held, self()})

        receive do
          :answer ->
            Req.Test.json(conn, %{"load" => %{"running" => 0, "queued" => 0, "maxWorkers" => 9}})
        after
          2_000 -> Req.Test.transport_error(conn, :timeout)
        end
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    render_async(view, 2_000)
    assert has_element?(view, "#flow-load [data-key='load-max']", "3")

    render_patch(view, ~p"/?repo=sallaumen/o_colmex")
    assert_receive {:held, agent}
    assert has_element?(view, "#flow-load [data-key='load-max']", "?")

    send(agent, :answer)
    render_async(view, 2_000)
    assert has_element?(view, "#flow-load [data-key='load-max']", "9")
  end

  test "an answer for another repository is dropped" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, repo: %{id: 1}, orchestrator: {:error, :unknown}}
    }

    answer = {:ok, %{running: 0, queued: 0, max_workers: 9}}
    assert BoardLive.handle_async(:orchestrator, {:ok, {2, answer}}, socket) == {:noreply, socket}
  end

  test "plus and minus save the new ceiling in the runner and the tile shows it", %{
    conn: conn,
    runner: runner
  } do
    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    html = render_async(view, 2_000)
    assert html =~ "Mais um agente"

    view |> element("#flow-load button[aria-label='Mais um agente']") |> render_click()

    assert [%{"revision" => 7, "value" => %{"maxWorkers" => 4}}] = Agent.get(runner, & &1.puts)
    assert has_element?(view, "#flow-load", "de")
    assert has_element?(view, "#flow-load [data-key='load-max']", "4")

    view |> element("#flow-load button[aria-label='Menos um agente']") |> render_click()
    assert has_element?(view, "#flow-load [data-key='load-max']", "3")
  end

  test "the minus button stops at one agent", %{conn: conn, runner: runner} do
    Agent.update(runner, &%{&1 | max: 1})
    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    render_async(view, 2_000)

    assert has_element?(view, "#flow-load button[aria-label='Menos um agente'][disabled]")
  end

  test "a conflict says the settings changed and writes nothing", %{conn: conn, runner: runner} do
    Agent.update(runner, &Map.put(&1, :conflict, true))
    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    render_async(view, 2_000)

    html = view |> element("#flow-load button[aria-label='Mais um agente']") |> render_click()

    assert html =~ "mudaram no painel do agente"
    assert has_element?(view, "#flow-load [data-key='load-max']", "3")
  end

  defp runner(%{method: "GET", request_path: "/orchestrator/api/state"} = conn, runner) do
    max = Agent.get(runner, & &1.max)
    Req.Test.json(conn, %{"load" => %{"running" => 1, "queued" => 0, "maxWorkers" => max}})
  end

  defp runner(%{method: "GET", request_path: "/orchestrator/api/settings"} = conn, runner) do
    %{max: max, revision: revision} = Agent.get(runner, & &1)

    Req.Test.json(conn, %{
      "blocks" => %{
        "executor" => %{"value" => Map.put(@executor, "maxWorkers", max), "revision" => revision}
      }
    })
  end

  defp runner(
         %{method: "PUT", request_path: "/orchestrator/api/settings/executor"} = conn,
         runner
       ) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    put = Jason.decode!(body)

    if Agent.get(runner, &Map.get(&1, :conflict, false)) do
      conn |> Plug.Conn.put_status(409) |> Req.Test.json(%{"error" => "Settings changed."})
    else
      Agent.update(runner, fn state ->
        %{
          state
          | max: put["value"]["maxWorkers"],
            revision: state.revision + 1,
            puts: state.puts ++ [put]
        }
      end)

      Req.Test.json(conn, %{"saved" => true, "revision" => 8, "restarting" => false})
    end
  end

  defp runner(conn, _runner), do: Req.Test.json(conn, %{})

  defp restore(key, nil), do: Application.delete_env(:agent_board, key)
  defp restore(key, value), do: Application.put_env(:agent_board, key, value)
end
