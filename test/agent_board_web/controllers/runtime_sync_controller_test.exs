defmodule AgentBoardWeb.RuntimeSyncControllerTest do
  use AgentBoardWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias AgentBoard.{Actions, Board, Superagents}
  alias AgentBoard.Superagents.RuntimeSync

  @projects "/?panel=settings&section=projects"

  test "management is local even if the browser knows the confirmation", %{conn: conn} do
    conn =
      post(%{conn | remote_ip: {192, 0, 2, 2}, host: "localhost"}, ~p"/superagents/synchronize",
        confirm: "update"
      )

    assert response(conn, 403)
    assert Actions.recent() == []
  end

  test "projects lists the scope; a stale click is refused and a current click skips a paused agent",
       %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "maintenance")

    {:ok, agent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "test-maint",
        port: 3311,
        state_dir: "/tmp/test-maint",
        desired_state: "paused"
      })

    conn = %{conn | host: "localhost"}
    {:ok, view, _} = live(conn, @projects)

    phrase =
      Actions.phrase(:sync_agent_runtimes, %{targets: %{agent.id => "fixture/maintenance"}})

    assert has_element?(view, "#runtime-targets", phrase)
    assert has_element?(view, "form[action='/superagents/synchronize'] button", "Sincronizar")

    assert post(conn, ~p"/superagents/synchronize", confirm: "old scope") |> redirected_to(303) ==
             @projects

    assert [%{decision: "refused"}] = Actions.recent()
    Superagents.subscribe()

    assert post(conn, ~p"/superagents/synchronize", confirm: phrase) |> redirected_to(303) ==
             @projects

    wait_for_completion()
    assert RuntimeSync.status().rows[agent.id] == "paused"
    assert render(view) =~ "Ignorado: agente pausado"
  end

  test "the manager checks load, identity, handoff and duplicate protection" do
    {output, status} =
      System.cmd("python3", ["-B", "-m", "unittest", "discover", "-s", "test/runtime_sync"],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "a second operator cannot change a profile while maintenance holds it" do
    test_pid = self()

    task =
      Task.async(fn ->
        RuntimeSync.exclusive(41, fn ->
          send(test_pid, :holding)

          receive do
            :done -> :ok
          end
        end)
      end)

    assert_receive :holding

    assert {:error, :control_in_progress} =
             RuntimeSync.exclusive(41, fn -> flunk("entered twice") end)

    assert :ok = RuntimeSync.exclusive(42, fn -> :ok end)
    send(task.pid, :done)
    assert :ok = Task.await(task)
  end

  defp wait_for_completion do
    assert_receive :runtime_sync_changed, 2000
    if RuntimeSync.status().running, do: wait_for_completion()
  end
end
