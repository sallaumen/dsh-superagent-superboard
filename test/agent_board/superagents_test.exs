defmodule AgentBoard.SuperagentsTest do
  @moduledoc "The registry owns profile/port/state per repository and keeps the lifecycle audit."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{AgentState, Board, Superagents}
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

  test "AgentState reads orchestrator.sqlite inside each registered state dir", %{repo: repo} do
    dir =
      Path.join(
        System.tmp_dir!(),
        "agent-state-paths-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    db_path = Path.join(dir, "orchestrator.sqlite")
    {:ok, conn} = Exqlite.Sqlite3.open(db_path)
    :ok = Exqlite.Sqlite3.execute(conn, "create table ticket (value text)")

    ticket = %{
      "mandate" => %{"basis" => %{"scope" => %{"number" => 126}}},
      "channels" => [
        %{
          "address" => %{
            "number" => "126",
            "url" => "https://github.com/fixture/superagent/issues/126"
          }
        }
      ],
      "assignments" => [
        %{
          "state" => "ended",
          "report" => %{"state" => "failed", "summary" => "tool input is invalid JSON"}
        }
      ],
      "updatedAt" => "2026-11-09T01:04:06.163Z"
    }

    value = ticket |> Jason.encode!() |> String.replace("'", "''")
    :ok = Exqlite.Sqlite3.execute(conn, "insert into ticket (value) values ('#{value}')")

    Exqlite.Sqlite3.close(conn)

    {:ok, _superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-state-path-test",
        port: 3299,
        state_dir: dir
      })

    previous = Application.get_env(:agent_board, :state_db)
    previous_dbs = Application.get_env(:agent_board, :state_dbs)
    Application.put_env(:agent_board, :state_db, nil)
    Application.put_env(:agent_board, :state_dbs, nil)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :state_db, previous),
        else: Application.delete_env(:agent_board, :state_db)

      if previous_dbs,
        do: Application.put_env(:agent_board, :state_dbs, previous_dbs),
        else: Application.delete_env(:agent_board, :state_dbs)

      File.rm_rf!(dir)
    end)

    assert AgentState.paths() == [db_path]
    assert [ticket] = AgentState.tickets()
    assert ticket["numbers"] == [126]
    assert ticket["report"] == "failed"
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

    assert {:error, changeset} = Superagents.create(Map.put(base, :max_workers, 17))
    assert changeset.errors[:max_workers]
  end

  test "scale refuses a ceiling above the agent's own limit", %{repo: repo} do
    {:ok, pid} = FakeManager.start()
    on_exit(fn -> if Process.alive?(pid), do: Agent.stop(pid) end)

    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-ceiling",
        port: 3195,
        state_dir: "/tmp/superagent-ceiling",
        max_workers: 16
      })

    assert {:error, :invalid_workers} = Superagents.scale(superagent, 17, FakeManager)
  end

  test "a settings change in between is a conflict, not an agent error", %{repo: repo} do
    {:ok, _pid} = FakeManager.start()
    on_exit(&stop_fake_manager/0)

    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-conflict",
        port: 3190,
        state_dir: "/tmp/superagent-conflict",
        max_workers: 3
      })

    {:ok, superagent} = Superagents.observe(superagent, %{state: "ready"})
    FakeManager.put_answer(superagent.id, :scale, {:error, :conflict})

    assert {:error, :conflict} = Superagents.scale(superagent, 4, FakeManager)

    assert %{observed_state: "ready", max_workers: 3, last_error: nil} =
             Repo.get!(Superagent, superagent.id)

    assert [%{action: "observe"}] = Superagents.events(superagent)
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

    # A start that times out still answers :ok, so an agent that dies at boot
    # would be started on every tick: the board waits before trying again.
    Superagents.reconcile(FakeManager)
    assert Repo.get!(Superagent, unreachable.id).observed_state == "error"

    Repo.update_all(
      from(e in AgentBoard.Superagents.SuperagentEvent,
        where: e.superagent_id == ^superagent.id and e.action == "start" and e.actor == "board"
      ),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -601, :second)]
    )

    Superagents.reconcile(FakeManager)
    assert Repo.get!(Superagent, unreachable.id).observed_state == "starting"

    {:ok, _} = Superagents.observe(Repo.get!(Superagent, unreachable.id), %{state: "ready"})
    assert Repo.get!(Superagent, unreachable.id).last_error == nil

    Superagents.set_desired(Repo.get!(Superagent, superagent.id), "stopped")
    FakeManager.put(superagent.id, %{state: "ready"})
    Superagents.reconcile(FakeManager)
    assert Repo.get!(Superagent, superagent.id).observed_state == "stopped"
  end

  # The decision behind "unknown": a status read the board had to kill is an
  # observation, so a desired-running agent whose read hangs takes the
  # auto_start branch on the next reconcile (bounded by the ten-minute wait
  # and the manager's refusal to start a duplicate). Recording "error" would
  # instead leave it to a person.
  test "a status read that times out is observed as unknown and then reconciled", %{repo: repo} do
    {:ok, _pid} = FakeManager.start()
    on_exit(&stop_fake_manager/0)

    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-slow",
        port: 3192,
        state_dir: "/tmp/fixture-superagent-slow"
      })

    {:ok, superagent} = Superagents.set_desired(superagent, "running")
    {:ok, superagent} = Superagents.observe(superagent, %{state: "ready"})

    FakeManager.put(superagent.id, %{state: "ready", delay_ms: 1_000})
    Superagents.tick(FakeManager)

    assert %{observed_state: "unknown", last_error: nil} = Repo.get!(Superagent, superagent.id)

    assert [%{action: "observe", from_state: "ready", to_state: "unknown", detail: detail} | _] =
             Superagents.events(superagent)

    assert detail == "status read timed out"

    Superagents.reconcile(FakeManager)
    assert Repo.get!(Superagent, superagent.id).observed_state == "starting"

    assert [%{action: "start", actor: "board", detail: "reconcile"}] =
             superagent |> Superagents.events() |> Enum.filter(&(&1.action == "start"))
  end

  test "a stop the manager refuses is asked once per pause, as the board", %{repo: repo} do
    {:ok, _pid} = FakeManager.start()
    on_exit(&stop_fake_manager/0)

    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-stuck",
        port: 3191,
        state_dir: "/tmp/fixture-superagent-stuck"
      })

    {:ok, superagent} = Superagents.set_desired(superagent, "stopped")
    FakeManager.put(superagent.id, %{state: "ready"})
    FakeManager.put_answer(superagent.id, :stop, {:error, :stuck})

    Superagents.tick(FakeManager)
    Superagents.reconcile(FakeManager)
    assert %{observed_state: "error", last_error: ":stuck"} = Repo.get!(Superagent, superagent.id)

    # The next read sees the process still up; the board waits before asking again.
    Superagents.tick(FakeManager)
    assert Repo.get!(Superagent, superagent.id).observed_state == "ready"
    Superagents.reconcile(FakeManager)

    assert [
             %{actor: "board", to_state: "error", detail: ":stuck"},
             %{actor: "board", to_state: "stopped", detail: "reconcile"}
           ] = superagent |> Superagents.events() |> Enum.filter(&(&1.action == "stop"))
  end

  defp stop_fake_manager do
    case Process.whereis(FakeManager) do
      nil ->
        :ok

      pid ->
        try do
          Agent.stop(pid)
        catch
          :exit, _ -> :ok
        end
    end
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

  test "a failed provision keeps a row to retry and records the reason", %{repo: repo} do
    {:ok, source_repo} = Board.add_repository("fixture", "source")

    {:ok, source} =
      Superagents.create(%{
        repository_id: source_repo.id,
        profile: "superagent-source",
        port: 3193,
        state_dir: "/tmp/source-superagent-retry"
      })

    assert {:error, "the bot cannot push"} =
             Superagents.provision(
               repo,
               source,
               %{path: "/tmp/checkout", fail: "the bot cannot push"},
               FakeProvisioner
             )

    assert %Superagent{observed_state: "error", provision_failed_at: %DateTime{}} =
             Superagents.get_by_repository(repo)

    assert [%{kind: "provision_error", payload: %{"reason" => "the bot cannot push"}}] =
             Board.events(repo) |> Enum.filter(&(&1.kind == "provision_error"))
  end

  test "a checkout that is not there gives the repository back to the form", %{repo: repo} do
    {:ok, source_repo} = Board.add_repository("fixture", "source")

    {:ok, source} =
      Superagents.create(%{
        repository_id: source_repo.id,
        profile: "superagent-source",
        port: 3195,
        state_dir: "/tmp/source-superagent-path"
      })

    assert {:error, :checkout_missing} =
             Superagents.provision(
               repo,
               source,
               %{path: "/tmp/typo", fail: :checkout_missing},
               FakeProvisioner
             )

    assert Superagents.get_by_repository(repo) == nil

    assert [%{payload: %{"reason" => "no git checkout at /tmp/typo"}}] =
             Board.events(repo) |> Enum.filter(&(&1.kind == "provision_error"))

    assert {:ok, %Superagent{}} =
             Superagents.provision(repo, source, %{path: "/tmp/checkout"}, FakeProvisioner)
  end

  test "an agent that would not stop keeps its card and is not restarted", %{repo: repo} do
    {:ok, source_repo} = Board.add_repository("fixture", "source")

    {:ok, source} =
      Superagents.create(%{
        repository_id: source_repo.id,
        profile: "superagent-source",
        port: 3194,
        state_dir: "/tmp/source-superagent-stuck"
      })

    assert {:error, message} =
             Superagents.provision(
               repo,
               source,
               %{path: "/tmp/checkout", fail: {:still_running, "the bot cannot push", "stuck"}},
               FakeProvisioner
             )

    assert message =~ "the bot cannot push"
    assert message =~ "the agent did not stop: stuck"

    superagent = Superagents.get_by_repository(repo)
    assert superagent.desired_state == "stopped"
    assert superagent.observed_state == "error"
    assert superagent.last_error =~ "did not stop"
    assert is_nil(superagent.provision_failed_at)
  end

  test "a detached job finishes after the caller is killed" do
    test = self()

    caller =
      spawn(fn ->
        Superagents.detached(fn ->
          send(test, {:job, self()})

          receive do
            :finish -> send(test, :finished)
          end
        end)
      end)

    assert_receive {:job, job}
    Process.exit(caller, :kill)
    refute Process.alive?(caller)
    send(job, :finish)
    assert_receive :finished
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

    assert AgentBoard.AgentState.paths() == [
             Path.join("/tmp/fixture-superagent-4", "orchestrator.sqlite")
           ]
  end

  defp with_profiles(tmp, fun) do
    File.mkdir_p!(Path.join(tmp, "superagent"))
    File.mkdir_p!(Path.join(tmp, "desktop"))

    File.write!(
      Path.join([tmp, "superagent", "cordis.patch.yml"]),
      "webserver:\n  port: 3082\n- id: dsh-superagent\n"
    )

    File.write!(Path.join([tmp, "desktop", "cordis.patch.yml"]), "webserver:\n  port: 3083\n")

    previous = Application.get_env(:agent_board, :dsh_profiles_dir)
    Application.put_env(:agent_board, :dsh_profiles_dir, tmp)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :dsh_profiles_dir, previous),
        else: Application.delete_env(:agent_board, :dsh_profiles_dir)

      File.rm_rf!(tmp)
    end)

    fun.()
  end

  test "profiles on disk carry their patch ports and the main profile is the default" do
    tmp = Path.join(System.tmp_dir!(), "dsh-profiles-#{System.unique_integer([:positive])}")

    with_profiles(tmp, fn ->
      profiles = Superagents.profiles_on_disk()
      assert Enum.map(profiles, & &1.name) == ["desktop", "superagent"]
      assert Enum.find(profiles, &(&1.name == "superagent")).port == 3082

      assert {:ok, source} = Superagents.default_source()
      assert source.profile == "superagent"
      assert source.port == 3082

      assert {:ok, other} = Superagents.source_by_profile("desktop")
      assert other.port == 3083
      assert {:error, :profile_missing} = Superagents.source_by_profile("nope")
    end)
  end

  test "a profile of the Harness itself is not an agent to copy" do
    tmp = Path.join(System.tmp_dir!(), "dsh-profiles-#{System.unique_integer([:positive])}")

    with_profiles(tmp, fn ->
      File.rm_rf!(Path.join(tmp, "superagent"))

      assert [%{name: "desktop", agent?: false}] = Superagents.profiles_on_disk()
      assert {:error, :no_working_profile} = Superagents.default_source()
    end)
  end

  test "a machine's first agent is provisioned with no profile to copy, and can be retried", %{
    repo: repo
  } do
    assert {:ok, %{source_profile: nil, profile: profile}} =
             Superagents.preview(repo, :first, %{workers: 2})

    assert {:error, :unreachable} =
             Superagents.provision(
               repo,
               :first,
               %{path: "/tmp/first", workers: 2, fail: :unreachable},
               FakeProvisioner
             )

    assert %{profile: ^profile, source_profile: nil, checkout_path: "/tmp/first"} =
             failed = Superagents.get_by_repository(repo)

    assert %DateTime{} = failed.provision_failed_at

    assert {:ok, _superagent} = Superagents.retry_provision(failed, FakeProvisioner)

    assert {_row, :first, %{path: "/tmp/first", workers: 2}} =
             Process.get({FakeProvisioner, :last})
  end

  test "without any profile on disk the default source is an error" do
    tmp = Path.join(System.tmp_dir!(), "dsh-profiles-empty-#{System.unique_integer([:positive])}")

    with_profiles(tmp, fn ->
      File.rm_rf!(tmp)
      File.mkdir_p!(tmp)
      assert {:error, :no_working_profile} = Superagents.default_source()
    end)
  end

  test "preview names the profile, port and state dir without writing", %{repo: repo} do
    tmp = Path.join(System.tmp_dir!(), "dsh-profiles-#{System.unique_integer([:positive])}")

    with_profiles(tmp, fn ->
      {:ok, source} = Superagents.default_source()
      assert {:ok, preview} = Superagents.preview(repo, source, %{workers: 4})
      assert preview.source_profile == "superagent"
      assert preview.profile =~ "superagent-superagent"
      assert preview.port in 3090..3199
      assert preview.workers == 4
      assert preview.state_dir == Path.expand("~/.dsh/state/#{preview.profile}")
      refute Superagents.get_by_repository(repo)
    end)
  end

  test "provision accepts a working-profile name as the source", %{repo: repo} do
    tmp = Path.join(System.tmp_dir!(), "dsh-profiles-#{System.unique_integer([:positive])}")

    with_profiles(tmp, fn ->
      assert {:ok, superagent} =
               Superagents.provision(
                 repo,
                 "superagent",
                 %{path: "/tmp/checkout", workers: 2},
                 FakeProvisioner
               )

      assert superagent.profile =~ "superagent-superagent"
      assert {_row, source, _attrs} = Process.get({FakeProvisioner, :last})
      assert source.profile == "superagent"
      assert source.port == 3082
    end)
  end

  describe "the manager's /state in a shape the board did not expect" do
    alias AgentBoard.Superagents.DshManager

    # A task of the ticker runs this; an exception there is linked to the
    # ticker, and a few in a row take the whole application down.
    for {label, body} <- [
          {"a list", ["x"]},
          {"text", "<html>bad gateway</html>"},
          {"health that is text", %{"health" => "ok"}},
          {"a health entry that is a number", %{"health" => %{"uptime" => 3}}},
          {"a runtime that is text", %{"health" => %{"runtime" => "ready"}}}
        ] do
      test "#{label} is an observed error" do
        assert %{state: "error"} = DshManager.observation(unquote(Macro.escape(body)))
      end
    end

    test "a good answer is still read" do
      body = %{"health" => %{"runtime" => %{"state" => "ready"}}, "load" => %{"running" => 1}}

      assert %{state: "ready", paused: false} = DshManager.observation(body)
    end
  end

  describe "a provisioning that failed" do
    defmodule FailingProvisioner do
      @behaviour AgentBoard.Superagents.Provisioner
      def first_ready, do: :ok
      def provision(_superagent, _source, _attrs), do: {:error, "the bot cannot push"}
    end

    setup %{repo: repo} do
      {:ok, source_repo} = Board.add_repository("fixture", "failed-source")

      {:ok, source} =
        Superagents.create(%{
          repository_id: source_repo.id,
          profile: "superagent",
          port: 3489,
          state_dir: "/tmp/failed-source"
        })

      {:ok, _pid} = FakeManager.start()

      root = Path.join(System.tmp_dir!(), "failed-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "superagent"))
      File.write!(Path.join([root, "superagent", "cordis.patch.yml"]), "port: 3489\n")
      Application.put_env(:agent_board, :dsh_profiles_dir, root)

      on_exit(fn ->
        Application.delete_env(:agent_board, :dsh_profiles_dir)
        File.rm_rf!(root)
      end)

      assert {:error, "the bot cannot push"} =
               Superagents.provision(
                 repo,
                 source,
                 %{path: "/tmp/checkout", workers: 2, port: 3488},
                 FailingProvisioner
               )

      {:ok, failed: Superagents.get_by_repository(repo)}
    end

    test "keeps the reason in words and what a retry needs", %{failed: failed} do
      assert failed.observed_state == "error"
      assert failed.last_error == "the bot cannot push"
      assert failed.provision_failed_at
      assert failed.checkout_path == "/tmp/checkout"
      assert failed.source_profile == "superagent"
    end

    test "is not started by the ticker or by hand", %{failed: failed} do
      FakeManager.put(failed.id, "stopped")
      Repo.update!(Superagent.changeset(failed, %{last_error: "econnrefused"}))

      Superagents.reconcile(FakeManager)

      assert Repo.get!(Superagent, failed.id).observed_state == "error"
      assert {:error, :provision_failed} = Superagents.start(failed, FakeManager)
    end

    test "the status read does not replace the reason", %{failed: failed} do
      Superagents.tick(FakeManager)

      assert Repo.get!(Superagent, failed.id).last_error == "the bot cannot push"
    end

    test "a retry that works clears the failure", %{failed: failed} do
      assert {:ok, _} = Superagents.retry_provision(failed, FakeProvisioner)

      retried = Repo.get!(Superagent, failed.id)
      assert is_nil(retried.provision_failed_at)
      assert retried.observed_state == "starting"
      assert is_nil(retried.last_error)

      assert {_row, %Superagent{profile: "superagent"}, %{path: "/tmp/checkout", workers: 2}} =
               Process.get({FakeProvisioner, :last})
    end

    test "a retry that fails stays retryable", %{failed: failed} do
      assert {:error, _} = Superagents.retry_provision(failed, FailingProvisioner)
      assert Repo.get!(Superagent, failed.id).provision_failed_at
    end

    test "a second retry from a stale screen finds nothing to do", %{failed: failed} do
      assert {:ok, _} = Superagents.retry_provision(failed, FakeProvisioner)
      Process.delete({FakeProvisioner, :last})

      assert {:error, :nothing_to_retry} = Superagents.retry_provision(failed, FakeProvisioner)
      refute Process.get({FakeProvisioner, :last})
    end

    test "a retry already running is not started again", %{failed: failed} do
      defmodule ReentrantProvisioner do
        @behaviour AgentBoard.Superagents.Provisioner

        def provision(superagent, _source, _attrs) do
          send(
            self(),
            {:inner,
             Superagents.retry_provision(superagent, AgentBoard.Superagents.FakeProvisioner)}
          )

          {:ok, %{}}
        end
      end

      assert {:ok, _} =
               Superagents.retry_provision(
                 failed,
                 AgentBoard.SuperagentsTest.ReentrantProvisioner
               )

      assert_received {:inner, {:error, :nothing_to_retry}}
    end

    test "a new project avoids a profile already on disk", %{repo: repo} do
      root = Application.fetch_env!(:agent_board, :dsh_profiles_dir)
      File.mkdir_p!(Path.join(root, "superagent-disk-taken"))
      {:ok, taken} = Board.add_repository("fixture", "disk-taken")

      assert {:ok, %{profile: profile}} =
               Superagents.preview(taken, "superagent", %{path: "/tmp/x"})

      refute profile == "superagent-disk-taken"
      assert repo
    end

    test "only a failed provisioning can be retried", %{repo: _repo} do
      {:ok, other} = Board.add_repository("fixture", "healthy")

      {:ok, healthy} =
        Superagents.create(%{
          repository_id: other.id,
          profile: "superagent-healthy",
          port: 3487,
          state_dir: "/tmp/healthy"
        })

      assert {:error, :nothing_to_retry} = Superagents.retry_provision(healthy, FakeProvisioner)
    end
  end

  # The profile lives under the configured root; a hard-coded ~/.dsh/profiles
  # would archive the real profile of the same name instead.
  test "remove archives the profile from the configured root and the state", %{repo: repo} do
    {:ok, _pid} = FakeManager.start()
    root = Path.join(System.tmp_dir!(), "remove-#{System.unique_integer([:positive])}")
    profiles = Path.join(root, "profiles")
    profile = "superagent-remove-#{System.unique_integer([:positive])}"
    state = Path.join(root, "state")
    File.mkdir_p!(Path.join(profiles, profile))
    File.write!(Path.join([profiles, profile, "marker"]), "profile")
    File.mkdir_p!(state)

    for {key, value} <- [
          dsh_profiles_dir: profiles,
          superagent_archive_root: Path.join(root, "archive")
        ] do
      previous = Application.get_env(:agent_board, key)
      Application.put_env(:agent_board, key, value)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:agent_board, key, previous),
          else: Application.delete_env(:agent_board, key)
      end)
    end

    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: profile,
        port: 3197,
        state_dir: state
      })

    FakeManager.put(superagent.id, "stopped")

    assert {:ok, archive} = Superagents.remove(superagent, FakeManager)
    assert File.read!(Path.join([archive, "profile", "marker"])) == "profile"
    refute File.exists?(Path.join(profiles, profile))
    assert File.dir?(Path.join(archive, "state"))
    assert Repo.get(Superagent, superagent.id) == nil
  end
end
