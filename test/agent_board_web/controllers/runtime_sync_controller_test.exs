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

    wait_for_result(agent.id, "paused")
    # Compare the receipt from the real controller with the installer's inputs.
    dir = Application.app_dir(:agent_board, "priv/agent")

    {digest, 0} =
      System.cmd(
        "python3",
        [
          "-B",
          "-c",
          "import sync_runtime; print(sync_runtime.package_digest())"
        ],
        cd: dir
      )

    assert Superagents.get(agent.id).runtime_sync["lock"] == String.trim(digest)
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

  test "a pending update survives its owner, coalesces clicks and completes only once idle", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "deferred")

    {:ok, agent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "test-deferred",
        port: 3312,
        state_dir: "/tmp/test-deferred"
      })

    {:ok, view, _html} = live(conn, @projects)
    owner = self()

    runner = fn _, _, _ ->
      send(owner, {:attempt, self()})

      receive do
        {:load, answer} -> answer
      end
    end

    opts = [name: :deferred_runtime_test, interval: :manual, runner: runner]
    worker = start_supervised!({RuntimeSync, opts})
    targets = RuntimeSync.targets([Superagents.get(agent.id)])
    Superagents.subscribe()
    assert :ok = RuntimeSync.start(targets, worker)
    assert_receive {:attempt, task}, 3_000
    send(task, {:load, "busy"})
    wait_for_result(agent.id, "pending")
    pending = Superagents.get(agent.id).runtime_sync
    assert render(view) =~ "Atualização pendente"

    stop_supervised!(RuntimeSync)
    worker = start_supervised!({RuntimeSync, opts})
    assert has_element?(view, "#project-#{agent.id} [role=status]", "Atualização pendente")
    send(worker, :tick)
    assert_receive {:attempt, next}, 3_000
    for _ <- 1..5, do: RuntimeSync.start(targets, worker)
    assert Superagents.get(agent.id).runtime_sync == pending
    send(next, {:load, "updated"})
    wait_for_result(agent.id, "updated")
    receipt = Superagents.get(agent.id).runtime_sync
    assert has_element?(view, "#project-sync-#{agent.id}", "Harness atualizado")
    assert {:ok, _, 0} = DateTime.from_iso8601(receipt["status_at"])
    {:ok, reopened, _} = live(conn, @projects)

    assert has_element?(
             reopened,
             "#project-sync-#{agent.id} time[datetime='#{receipt["status_at"]}']"
           )

    assert has_element?(reopened, "#project-sync-#{agent.id}", "Harness atualizado")
    send(worker, :tick)
    refute_receive {:attempt, _}

    assert :ok = RuntimeSync.start(targets, worker)
    assert_receive {:attempt, check}, 3_000
    send(check, {:load, "current"})
    wait_for_result(agent.id, "current")
    {:ok, reopened, _} = live(conn, @projects)
    assert has_element?(reopened, "#project-sync-#{agent.id}[data-status=current] time")
    refute has_element?(reopened, "#project-sync-#{agent.id}[data-status=updated]")
  end

  defp wait_for_result(id, expected) do
    assert_receive :runtime_sync_changed, 3000

    unless Superagents.get(id).runtime_sync["status"] == expected,
      do: wait_for_result(id, expected)
  end
end
