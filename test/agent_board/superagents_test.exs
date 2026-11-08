defmodule AgentBoard.SuperagentsTest do
  @moduledoc "The registry owns profile/port/state per repository and keeps the lifecycle audit."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Board, Superagents}
  alias AgentBoard.Superagents.{FakeManager, FakeProvisioner, Superagent}

  setup do
    {:ok, repo} = Board.add_repository("fixture", "superagent")
    %{repo: repo}
  end

  test "one row per repository, with explicit state paths", %{repo: repo} do
    assert {:ok, superagent} =
             Superagents.create(%{
               repository_id: repo.id,
               profile: "superagent-fixture",
               port: 3199,
               state_dir: "/tmp/fixture-superagent",
               max_workers: 2
             })

    assert [row] = Superagents.list()
    assert row.repository.name == "superagent"
    assert Superagents.state_paths() == ["/tmp/fixture-superagent"]
    assert Superagents.get_by_repository(repo).id == superagent.id

    assert {:error, changeset} =
             Superagents.create(%{
               repository_id: repo.id,
               profile: "superagent-other",
               port: 3200,
               state_dir: "/tmp/other"
             })

    assert changeset.errors[:repository_id]
  end

  test "an unchanged observation does not add an event; a change does", %{repo: repo} do
    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-fixture",
        port: 3198,
        state_dir: "/tmp/fixture-superagent-2"
      })

    assert {:ok, _} = Superagents.observe(superagent, %{state: "unknown"})
    assert Superagents.events(superagent) == []

    assert {:ok, updated} =
             Superagents.observe(superagent, %{state: "ready", detail: "ok"})

    assert updated.observed_state == "ready"
    assert [event] = Superagents.events(superagent)
    assert event.action == "observe"
    assert event.to_state == "ready"
  end

  test "desired state and scale are audited", %{repo: repo} do
    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-fixture",
        port: 3197,
        state_dir: "/tmp/fixture-superagent-3"
      })

    assert {:ok, stopped} = Superagents.set_desired(superagent, "stopped")
    assert stopped.desired_state == "stopped"

    assert {:ok, scaled} = Superagents.set_max_workers(stopped, 5)
    assert scaled.max_workers == 5
    assert length(Superagents.events(scaled)) == 2
  end

  test "the schema rejects an invalid state, port and worker count", %{repo: repo} do
    base = %{repository_id: repo.id, profile: "x", port: 3196, state_dir: "/tmp/x"}

    assert {:error, changeset} = Superagents.create(Map.put(base, :desired_state, "dancing"))
    assert changeset.errors[:desired_state]

    assert {:error, changeset} = Superagents.create(Map.put(base, :max_workers, 0))
    assert changeset.errors[:max_workers]
  end

  test "tick records the manager observation", %{repo: repo} do
    {:ok, _pid} = FakeManager.start()

    on_exit(fn ->
      case Process.whereis(FakeManager) do
        nil ->
          :ok

        pid ->
          if Process.alive?(pid),
            do:
              (try do
                 Agent.stop(pid)
               catch
                 :exit, _ -> :ok
               end)
      end
    end)

    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-fixture",
        port: 3194,
        state_dir: "/tmp/fixture-superagent-5"
      })

    FakeManager.put(superagent.id, %{state: "ready", detail: nil})
    Superagents.tick(FakeManager)

    assert Repo.get!(Superagent, superagent.id).observed_state == "ready"
    assert [%{action: "observe", to_state: "ready"}] = Superagents.events(superagent)
  end

  test "reconcile starts a stopped desired-running agent and stops a stopped one", %{repo: repo} do
    {:ok, _pid} = FakeManager.start()

    on_exit(fn ->
      case Process.whereis(FakeManager) do
        nil ->
          :ok

        pid ->
          if Process.alive?(pid),
            do:
              (try do
                 Agent.stop(pid)
               catch
                 :exit, _ -> :ok
               end)
      end
    end)

    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-fixture",
        port: 3193,
        state_dir: "/tmp/fixture-superagent-6"
      })

    {:ok, superagent} = Superagents.set_desired(superagent, "running")
    {:ok, superagent} = Superagents.observe(superagent, %{state: "stopped"})

    Superagents.reconcile(FakeManager)
    assert Repo.get!(Superagent, superagent.id).observed_state == "starting"

    unreachable = Repo.get!(Superagent, superagent.id)

    {:ok, unreachable} =
      Superagents.observe(unreachable, %{state: "error", detail: "econnrefused"})

    Superagents.reconcile(FakeManager)
    assert Repo.get!(Superagent, unreachable.id).observed_state == "starting"

    Superagents.set_desired(Repo.get!(Superagent, superagent.id), "stopped")
    FakeManager.put(superagent.id, %{state: "ready"})
    Superagents.reconcile(FakeManager)
    assert Repo.get!(Superagent, superagent.id).observed_state == "stopped"
  end

  test "provision reserves one row and asks the provisioner", %{repo: repo} do
    {:ok, source_repo} = Board.add_repository("fixture", "source")

    {:ok, source} =
      Superagents.create(%{
        repository_id: source_repo.id,
        profile: "superagent-source",
        port: 3192,
        state_dir: "/tmp/source-superagent"
      })

    assert {:ok, superagent} =
             Superagents.provision(
               repo,
               source,
               %{path: "/tmp/checkout", workers: 2},
               FakeProvisioner
             )

    assert superagent.profile =~ "superagent-superagent"
    assert superagent.port in 3090..3199
    assert superagent.max_workers == 2
    assert Repo.get!(Superagent, superagent.id).observed_state == "starting"

    assert {:error, :already_registered} =
             Superagents.provision(repo, source, %{path: "/tmp/checkout"}, FakeProvisioner)
  end

  test "AgentState uses the registered state paths", %{repo: repo} do
    {:ok, _} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-fixture",
        port: 3195,
        state_dir: "/tmp/fixture-superagent-4"
      })

    previous = Application.get_env(:agent_board, :state_db)
    Application.put_env(:agent_board, :state_db, nil)
    on_exit(fn -> Application.put_env(:agent_board, :state_db, previous) end)

    assert AgentBoard.AgentState.paths() == ["/tmp/fixture-superagent-4"]
  end
end
