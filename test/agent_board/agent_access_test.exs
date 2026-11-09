defmodule AgentBoard.AgentAccessTest do
  @moduledoc "Who may use each superagent: reading refusals, clearing, revoking, dismissing."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Actions, AgentAccess, Board, Superagents}
  alias AgentBoard.AgentAccess.Refusals
  alias AgentBoard.Superagents.{FakeManager, Superagent}

  setup do
    {:ok, manager} = FakeManager.start()
    previous = Application.get_env(:agent_board, :superagent_manager)
    Application.put_env(:agent_board, :superagent_manager, FakeManager)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :superagent_manager, previous),
        else: Application.delete_env(:agent_board, :superagent_manager)

      if Process.alive?(manager), do: Agent.stop(manager)
    end)

    state_dir = Path.join(System.tmp_dir!(), "agent-access-#{System.unique_integer([:positive])}")
    File.mkdir_p!(state_dir)
    on_exit(fn -> File.rm_rf!(state_dir) end)

    {:ok, repo} = Board.add_repository("fixture", "access-#{System.unique_integer([:positive])}")

    {:ok, superagent} =
      Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-access-#{repo.id}",
        port: 3400 + rem(repo.id, 1000),
        state_dir: state_dir
      })

    {:ok, repo: repo, superagent: Repo.preload(superagent, :repository), state_dir: state_dir}
  end

  defp database!(state_dir, build) do
    {:ok, conn} = Exqlite.Sqlite3.open(Path.join(state_dir, "orchestrator.sqlite"))

    for sql <- [
          "CREATE TABLE IF NOT EXISTS trigger (id TEXT PRIMARY KEY, value TEXT NOT NULL, at TEXT NOT NULL)",
          "CREATE TABLE IF NOT EXISTS decision (id TEXT PRIMARY KEY, thread TEXT NOT NULL, value TEXT NOT NULL)",
          "CREATE TABLE IF NOT EXISTS thread (key TEXT PRIMARY KEY, value TEXT NOT NULL)"
        ] do
      :ok = Exqlite.Sqlite3.execute(conn, sql)
    end

    build.(conn)
    :ok = Exqlite.Sqlite3.close(conn)
  end

  defp insert!(conn, table, values) do
    marks = Enum.map_join(values, ", ", fn _ -> "?" end)
    {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "INSERT INTO #{table} VALUES (#{marks})")
    :ok = Exqlite.Sqlite3.bind(statement, values)
    :done = Exqlite.Sqlite3.step(conn, statement)
    :ok = Exqlite.Sqlite3.release(conn, statement)
  end

  defp mention!(conn, id, login, number, at, overrides \\ %{}) do
    trigger =
      Map.merge(
        %{
          id: id,
          source: "github",
          actor: %{source: "github", id: login},
          human: true,
          at: at,
          addressed: "mention",
          url: "https://github.com/fixture/access/issues/#{number}",
          meta: %{number: number, isPr: false, kind: "issue"}
        },
        overrides
      )
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    insert!(conn, "trigger", [id, Jason.encode!(trigger), at])
    refuse!(conn, id, number, at)
    insert_thread!(conn, number)
  end

  defp refuse!(conn, trigger_id, number, at) do
    decision = %{
      id: "d-#{trigger_id}",
      kind: "ignore",
      at: at,
      reason: [%{code: "not_a_member", triggerId: trigger_id}]
    }

    insert!(conn, "decision", ["d-#{trigger_id}", "github:#{number}", Jason.encode!(decision)])
  end

  defp accept!(conn, id, number, at) do
    decision = %{id: id, kind: "accept", at: at, reason: [%{code: "explicitRouted"}]}
    insert!(conn, "decision", [id, "github:#{number}", Jason.encode!(decision)])
  end

  defp insert_thread!(conn, number) do
    thread = %{meta: %{title: "Issue #{number}"}}

    insert!(conn, "thread", ["github:#{number}", Jason.encode!(thread)])
  rescue
    MatchError -> :already_there
  end

  describe "Refusals.read/1" do
    test "reads who mentioned the bot and was refused, newest first", %{state_dir: state_dir} do
      database!(state_dir, fn conn ->
        mention!(conn, "t1", "amiga", 10, "2026-11-09T10:00:00.000Z")
        mention!(conn, "t2", "colega", 11, "2026-11-09T11:00:00.000Z")
      end)

      assert {:ok, [%{login: "colega", number: 11, title: "Issue 11"}, %{login: "amiga"}]} =
               Refusals.read(state_dir)
    end

    test "an issue that never mentioned the bot is not a request", %{state_dir: state_dir} do
      database!(state_dir, fn conn ->
        mention!(conn, "t1", "amiga", 10, "2026-11-09T10:00:00.000Z", %{addressed: nil})
      end)

      assert {:ok, []} = Refusals.read(state_dir)
    end

    test "a bot's message is not a request", %{state_dir: state_dir} do
      database!(state_dir, fn conn ->
        mention!(conn, "t1", "robo", 10, "2026-11-09T10:00:00.000Z", %{human: false})
      end)

      assert {:ok, []} = Refusals.read(state_dir)
    end

    test "marks a refusal the agent later accepted on the same issue", %{state_dir: state_dir} do
      database!(state_dir, fn conn ->
        mention!(conn, "t1", "amiga", 10, "2026-11-09T10:00:00.000Z")
        accept!(conn, "a1", 10, "2026-11-09T12:00:00.000Z")
      end)

      assert {:ok, [%{handled: true}]} = Refusals.read(state_dir)
    end

    test "a missing database is an error, and nothing is created", %{state_dir: state_dir} do
      assert {:error, _reason} = Refusals.read(state_dir)
      refute File.exists?(Path.join(state_dir, "orchestrator.sqlite"))
    end
  end

  describe "overview/2" do
    test "groups the mentions of one person and hides whoever is cleared", context do
      %{superagent: superagent, state_dir: state_dir} = context
      FakeManager.put_access(superagent.id, ["sallaumen", "Liberada"])

      database!(state_dir, fn conn ->
        mention!(conn, "t1", "amiga", 10, "2026-11-09T10:00:00.000Z")
        mention!(conn, "t2", "amiga", 11, "2026-11-09T11:00:00.000Z")
        mention!(conn, "t3", "amiga", 11, "2026-11-09T11:30:00.000Z")
        mention!(conn, "t4", "liberada", 12, "2026-11-09T12:00:00.000Z")
      end)

      assert [project] = AgentAccess.overview([superagent])
      assert project.state == :ok
      assert Enum.map(project.allowed, & &1.login) == ["sallaumen", "Liberada"]
      assert [request] = project.requests
      assert request.login == "amiga"
      assert request.mentions == 3
      assert Enum.map(request.issues, & &1.number) == [11, 10]
      assert %{number: 11, trigger_id: "t3"} in request.rerun
      assert MapSet.equal?(project.refused, MapSet.new([10, 11]))
    end

    test "an issue already finished, or accepted later, does not run again", context do
      %{superagent: superagent, state_dir: state_dir, repo: repo} = context
      FakeManager.put_access(superagent.id, ["sallaumen"])

      {:ok, _task} =
        %Board.Task{}
        |> Board.Task.changeset(%{
          repository_id: repo.id,
          kind: "issue",
          number: 20,
          title: "Pronta",
          state: "done",
          url: "https://github.com/fixture/access/issues/20"
        })
        |> Repo.insert()

      database!(state_dir, fn conn ->
        mention!(conn, "t1", "amiga", 20, "2026-11-09T10:00:00.000Z")
        mention!(conn, "t2", "amiga", 21, "2026-11-09T10:00:00.000Z")
        accept!(conn, "a1", 21, "2026-11-09T12:00:00.000Z")
        mention!(conn, "t3", "amiga", 22, "2026-11-09T10:00:00.000Z")
      end)

      assert [%{requests: [request]} = project] = AgentAccess.overview([superagent])
      assert request.rerun == [%{number: 22, trigger_id: "t3"}]
      assert MapSet.equal?(project.refused, MapSet.new([20, 22]))
    end

    test "an agent that does not answer is unavailable, not empty", context do
      %{superagent: superagent} = context
      FakeManager.put_access(superagent.id, {:error, :econnrefused})

      assert [%{state: :unavailable, reason: :econnrefused}] = AgentAccess.overview([superagent])
    end

    test "a failed read keeps the last good lists, marked unavailable", context do
      %{superagent: superagent} = context
      FakeManager.put_access(superagent.id, ["sallaumen", "amiga"])
      [good] = AgentAccess.overview([superagent])

      FakeManager.put_access(superagent.id, {:error, :econnrefused})
      [kept] = AgentAccess.keep_last_good([good], AgentAccess.overview([superagent]))

      assert kept.state == :unavailable
      assert Enum.map(kept.allowed, & &1.login) == ["sallaumen", "amiga"]
    end

    test "summary counts the people waiting and names the refused issues", context do
      %{superagent: superagent, state_dir: state_dir, repo: repo} = context
      FakeManager.put_access(superagent.id, ["sallaumen"])

      database!(state_dir, fn conn ->
        mention!(conn, "t1", "amiga", 10, "2026-11-09T10:00:00.000Z")
      end)

      summary = superagent |> List.wrap() |> AgentAccess.overview() |> AgentAccess.summary()

      assert summary.count == 1
      assert MapSet.member?(summary.refused, {repo.id, 10})
    end
  end

  describe "normalize_login/1" do
    test "accepts a login with or without the @" do
      assert {:ok, "ana-maria"} = AgentAccess.normalize_login("  @ana-maria ")
    end

    test "refuses what could reach a URL or is not a login" do
      for bad <- ["", "a/b", "../x", "a b", "-x", "dependabot[bot]", String.duplicate("a", 40), 1] do
        assert {:error, :invalid_login} = AgentAccess.normalize_login(bad)
      end
    end
  end

  describe "grant/4" do
    test "clears the person and runs again only what was asked", %{superagent: superagent} do
      FakeManager.put_access(superagent.id, ["sallaumen"])

      assert {:ok, %{login: "amiga", requeued: [10], failed: []}} =
               AgentAccess.grant(superagent, "@amiga", [%{number: 10, trigger_id: "t1"}])

      assert {:ok, %{allowed: allowed}} = FakeManager.access(superagent)
      assert Enum.map(allowed, & &1.login) == ["sallaumen", "amiga"]
      assert FakeManager.requeued(superagent.id) == ["t1"]
    end

    test "a re-run that fails keeps the clearance and names the issue", %{superagent: superagent} do
      FakeManager.put_access(superagent.id, [])
      FakeManager.put_requeue_answer(superagent.id, {:ok, false})

      assert {:ok, %{requeued: [], failed: [10]}} =
               AgentAccess.grant(superagent, "amiga", [%{number: 10, trigger_id: "t1"}])

      assert {:ok, %{allowed: [%{login: "amiga"}]}} = FakeManager.access(superagent)
    end

    test "never runs more than the limit from one confirmation", %{superagent: superagent} do
      FakeManager.put_access(superagent.id, [])
      limit = AgentAccess.rerun_limit()
      rerun = for number <- 1..(limit + 3), do: %{number: number, trigger_id: "t#{number}"}

      assert {:ok, %{requeued: requeued}} = AgentAccess.grant(superagent, "amiga", rerun)
      assert length(requeued) == limit
    end

    test "an invalid login reaches nothing", %{superagent: superagent} do
      FakeManager.put_access(superagent.id, [])

      assert {:error, :invalid_login} = AgentAccess.grant(superagent, "a/b")
      assert {:ok, %{allowed: []}} = FakeManager.access(superagent)
    end
  end

  describe "revoke/3" do
    test "takes a person off the list", %{superagent: superagent} do
      FakeManager.put_access(superagent.id, ["sallaumen", "amiga"])

      assert {:ok, "amiga"} = AgentAccess.revoke(superagent, "amiga")
      assert {:ok, %{allowed: [%{login: "sallaumen"}]}} = FakeManager.access(superagent)
    end

    test "refuses the repository's owner, whatever the case", %{superagent: superagent} do
      FakeManager.put_access(superagent.id, ["fixture"])

      assert {:error, :owner_protected} = AgentAccess.revoke(superagent, "FIXTURE")
      assert {:ok, %{allowed: [%{login: "fixture"}]}} = FakeManager.access(superagent)
    end
  end

  describe "dismiss/2" do
    test "hides a request until a newer mention", context do
      %{superagent: superagent, state_dir: state_dir} = context
      FakeManager.put_access(superagent.id, [])

      database!(state_dir, fn conn ->
        mention!(conn, "t1", "Amiga", 10, "2026-01-01T10:00:00.000Z")
      end)

      assert {:ok, _dismissal} = AgentAccess.dismiss(superagent, "Amiga")
      assert [%{requests: []}] = AgentAccess.overview([superagent])

      database!(state_dir, fn conn ->
        mention!(conn, "t2", "amiga", 11, "2099-01-01T10:00:00.000Z")
      end)

      assert [%{requests: [%{mentions: 2}]}] = AgentAccess.overview([superagent])
    end

    test "dismissing twice keeps one record", %{superagent: superagent} do
      assert {:ok, _} = AgentAccess.dismiss(superagent, "amiga")
      assert {:ok, _} = AgentAccess.dismiss(superagent, "AMIGA")
      assert Repo.aggregate(AgentBoard.AgentAccess.Dismissal, :count) == 1
    end
  end

  describe "the registry" do
    test "clearing needs the sentence that names the person and the cost", context do
      %{superagent: superagent} = context
      FakeManager.put_access(superagent.id, [])
      params = %{superagent: superagent, login: "amiga", rerun: [%{number: 10, trigger_id: "t1"}]}
      phrase = Actions.phrase(:grant_agent_access, params)

      assert phrase =~ "@amiga"
      assert phrase =~ "fixture/access"
      assert phrase =~ "merge sem revisão"
      assert phrase =~ "#10"

      assert {:error, {:unconfirmed, ^phrase}} =
               Actions.run(:grant_agent_access, params, Actions.owner(:ui))

      assert {:ok, %{allowed: []}} = FakeManager.access(superagent)

      assert {:ok, text} =
               Actions.run(:grant_agent_access, params, Actions.owner(:ui), confirm: phrase)

      assert text =~ "@amiga liberado"
      assert text =~ "#10"
    end

    test "a sentence for other issues is refused", %{superagent: superagent} do
      FakeManager.put_access(superagent.id, [])
      params = %{superagent: superagent, login: "amiga", rerun: []}
      other = %{params | rerun: [%{number: 99, trigger_id: "t9"}]}

      assert {:error, {:phrase_changed, _}} =
               Actions.run(:grant_agent_access, other, Actions.owner(:ui),
                 confirm: Actions.phrase(:grant_agent_access, params)
               )

      assert {:ok, %{allowed: []}} = FakeManager.access(superagent)
    end

    test "revoking the owner comes back as one sentence", %{superagent: superagent} do
      FakeManager.put_access(superagent.id, ["fixture"])
      params = %{superagent: superagent, login: "fixture"}

      assert {:error, text} =
               Actions.run(:revoke_agent_access, params, Actions.owner(:ui),
                 confirm: Actions.phrase(:revoke_agent_access, params)
               )

      assert text =~ "dono do repositório"
    end

    test "dismissing runs on the click and leaves a decision", %{superagent: superagent} do
      params = %{superagent: superagent, login: "amiga"}

      assert {:ok, _text} = Actions.run(:dismiss_access_request, params, Actions.owner(:ui))
      assert Actions.risk(:dismiss_access_request) == :yellow
    end

    test "every write announces the change to open boards", %{superagent: superagent} do
      FakeManager.put_access(superagent.id, [])
      Superagents.subscribe()

      assert {:ok, _} = AgentAccess.grant(superagent, "amiga")
      assert_received :agent_access_changed
    end
  end

  describe "announce_if_changed/1" do
    test "announces a change once, not on every read", %{superagent: superagent} do
      FakeManager.put_access(superagent.id, ["fixture"])
      Superagents.subscribe()

      fingerprint = AgentAccess.announce_if_changed(nil)
      assert_received :agent_access_changed

      assert AgentAccess.announce_if_changed(fingerprint) == fingerprint
      refute_received :agent_access_changed

      FakeManager.put_access(superagent.id, ["fixture", "amiga"])
      assert AgentAccess.announce_if_changed(fingerprint) != fingerprint
      assert_received :agent_access_changed
    end
  end

  describe "the DSH adapter" do
    alias AgentBoard.Superagents.DshManager

    # A small HTTP stand-in for the agent's management API.
    setup do
      test_pid = self()
      port = free_port()

      plug = fn conn, _opts ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:request, conn.method, conn.request_path, body})

        {status, response} =
          Agent.get(:fake_policy_api, & &1).(conn.method, conn.request_path, body)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(status, Jason.encode!(response))
      end

      {:ok, _} = Agent.start_link(fn -> nil end, name: :fake_policy_api)
      start_supervised!({Bandit, plug: plug, port: port, ip: {127, 0, 0, 1}, startup_log: false})

      {:ok, port: port}
    end

    defp free_port do
      {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
      {:ok, port} = :inet.port(socket)
      :gen_tcp.close(socket)
      port
    end

    defp answer(fun), do: Agent.update(:fake_policy_api, fn _ -> fun end)

    defp settings(allowed, revision \\ 7) do
      %{
        "blocks" => %{
          "policy" => %{
            "revision" => revision,
            "value" => %{
              "rules" => [%{"id" => "copy", "enabled" => true}],
              "sources" => %{
                "github" => %{"allowed" => allowed, "admission" => %{}, "bots" => []}
              }
            }
          }
        }
      }
    end

    test "allow appends the id, keeps the rest and sends the revision", %{port: port} do
      answer(fn
        "GET", _path, _body -> {200, settings([%{"id" => "sallaumen", "name" => "Dono"}])}
        "PUT", _path, _body -> {200, %{"saved" => true}}
      end)

      assert :ok = DshManager.allow(%Superagent{port: port}, "amiga")
      assert_received {:request, "PUT", "/orchestrator/api/settings/policy", body}

      assert %{"revision" => 7, "value" => value} = Jason.decode!(body)
      assert value["rules"] == [%{"id" => "copy", "enabled" => true}]

      assert value["sources"]["github"]["allowed"] == [
               %{"id" => "sallaumen", "name" => "Dono"},
               %{"id" => "amiga"}
             ]
    end

    test "someone already listed, in any case, writes nothing", %{port: port} do
      answer(fn "GET", _path, _body -> {200, settings([%{"id" => "Amiga"}])} end)

      assert :ok = DshManager.allow(%Superagent{port: port}, "amiga")
      refute_received {:request, "PUT", _path, _body}
    end

    test "a save in between is a conflict", %{port: port} do
      answer(fn
        "GET", _path, _body -> {200, settings([])}
        "PUT", _path, _body -> {409, %{"code" => "conflict"}}
      end)

      assert {:error, :conflict} = DshManager.allow(%Superagent{port: port}, "amiga")
    end

    test "disallow removes only that person", %{port: port} do
      answer(fn
        "GET", _path, _body -> {200, settings([%{"id" => "a"}, %{"id" => "B"}])}
        "PUT", _path, _body -> {200, %{"saved" => true}}
      end)

      assert :ok = DshManager.disallow(%Superagent{port: port}, "b")
      assert_received {:request, "PUT", _path, body}
      assert Jason.decode!(body)["value"]["sources"]["github"]["allowed"] == [%{"id" => "a"}]
    end

    test "access reads the people and survives an unexpected shape", %{port: port} do
      answer(fn "GET", _path, _body ->
        {200, settings([%{"id" => "amiga", "name" => "Ana"}, %{"oops" => true}])}
      end)

      assert {:ok, %{allowed: [%{login: "amiga", name: "Ana"}]}} =
               DshManager.access(%Superagent{port: port})

      answer(fn "GET", _path, _body -> {200, %{"nothing" => true}} end)
      assert {:error, :malformed} = DshManager.access(%Superagent{port: port})
    end

    test "requeue asks for that trigger", %{port: port} do
      answer(fn "POST", _path, _body -> {200, %{"queued" => true}} end)

      assert {:ok, true} = DshManager.requeue(%Superagent{port: port}, "abc123")
      assert_received {:request, "POST", "/orchestrator/api/triggers/abc123/requeue", _body}
    end
  end
end
