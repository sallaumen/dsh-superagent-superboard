defmodule AgentBoard.LiveTest do
  @moduledoc "The live poller: the ticket overlay in real time."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{Comment, Repository, Task}

  @sqlite "create table ticket (value text);"

  @running ~s({"mandate":{"basis":{"scope":{"number":42}}},"assignments":[{"state":"running"}]})
  @stopped ~s({"mandate":{"basis":{"scope":{"number":42}}},"assignments":[{"state":"running"}],"stopped":true})

  # The PubSub topic is the repository id, and every test sandbox starts its
  # ids at 1: another test creating a repository would broadcast into this
  # test's `board:1` subscription. An id out of the sandbox range keeps the
  # topic private. Inserting directly (not Board.add_repository/2) also skips
  # the insert broadcast, so assert_receive below proves the poll broadcast.
  defp isolated_repo do
    %Repository{}
    |> Repository.changeset(%{owner: "sallaumen", name: "arena-rogue"})
    |> Ecto.Changeset.put_change(:id, 1_000_000 + System.unique_integer([:positive]))
    |> Repo.insert!()
  end

  setup do
    # The pid keeps the path unique across VMs: a fresh `mix test` restarts
    # the unique_integer counter, and a file a previous VM failed to remove
    # would collide with the same counter value.
    path =
      Path.join(
        System.tmp_dir!(),
        "live-test-#{System.pid()}-#{System.unique_integer([:positive])}.sqlite"
      )

    File.rm(path)

    previous = Application.get_env(:agent_board, :state_db)

    {:ok, db} = Exqlite.Sqlite3.open(path)

    on_exit(fn ->
      Exqlite.Sqlite3.close(db)
      File.rm(path)
      if previous, do: Application.put_env(:agent_board, :state_db, previous)
    end)

    :ok = Exqlite.Sqlite3.execute(db, @sqlite)
    Application.put_env(:agent_board, :state_db, path)

    %{db: db}
  end

  defp task(repo) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 42,
      title: "Live task",
      state: "queued"
    })
    |> Repo.insert!()
  end

  test "the poller overlays the ticket state and broadcasts", %{db: db} do
    repo = isolated_repo()
    t = task(repo)

    :ok = Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('" <> @running <> "')")

    Board.subscribe(repo.id)
    AgentBoard.Live.poll(%{})

    assert_receive :board_updated
    assert Repo.get(Task, t.id).state == "running"
  end

  test "a second poll with the same tickets does not broadcast again", %{db: db} do
    repo = isolated_repo()

    :ok = Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('" <> @running <> "')")

    Board.subscribe(repo.id)

    state = AgentBoard.Live.poll(%{})
    assert_receive :board_updated

    _state = AgentBoard.Live.poll(state)
    refute_receive :board_updated, 150
  end

  test "a stopped ticket is not overlaid", %{db: db} do
    repo = isolated_repo()
    t = task(repo)

    :ok = Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('" <> @stopped <> "')")

    AgentBoard.Live.poll(%{})

    assert Repo.get(Task, t.id).state == "queued"
  end

  test "a done task is not revived by a stale ticket", %{db: db} do
    repo = isolated_repo()
    t = task(repo)
    t |> Task.changeset(%{state: "done"}) |> Repo.update!()

    :ok = Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('" <> @running <> "')")

    AgentBoard.Live.poll(%{})

    assert Repo.get(Task, t.id).state == "done"
  end

  @waiting_pr ~s({"mandate":{"basis":{"scope":{"number":42}}},"assignments":[{"state":"running","idleAt":"2026-11-06T19:44:05.231Z","report":{"state":"waiting","summary":"No code change made; the PR remains open."}}],"follows":[{"thread":"github:28","own":true}]})
  @waiting_quiet ~s({"mandate":{"basis":{"scope":{"number":42}}},"assignments":[{"state":"running","idleAt":"2026-11-06T19:44:05.231Z","report":{"state":"waiting","summary":"Cannot reach the registry."}}]})

  test "a waiting ticket that opened a PR is a review, not a question", %{db: db} do
    repo = isolated_repo()
    t = task(repo)

    :ok =
      Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('" <> @waiting_pr <> "')")

    AgentBoard.Live.poll(%{})

    assert Repo.get(Task, t.id).state == "ready"
  end

  test "a waiting ticket without a question or a PR is blocked", %{db: db} do
    repo = isolated_repo()
    t = task(repo)

    :ok =
      Exqlite.Sqlite3.execute(
        db,
        "insert into ticket (value) values ('" <> @waiting_quiet <> "')"
      )

    AgentBoard.Live.poll(%{})

    assert Repo.get(Task, t.id).state == "blocked"
  end

  test "a waiting ticket whose newest agent comment asks is a question", %{db: db} do
    repo = isolated_repo()
    t = task(repo)

    %Comment{}
    |> Comment.changeset(%{
      task_id: t.id,
      github_id: 1,
      author: "sallaumen-agent",
      body: "Devo manter o chefe na onda 5?\n\n<!-- dsh-superagent:abc -->",
      kind: "agent"
    })
    |> Repo.insert!()

    :ok =
      Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('" <> @waiting_pr <> "')")

    AgentBoard.Live.poll(%{})

    assert Repo.get(Task, t.id).state == "question"
  end

  test "the poller schedules the next tick", %{db: _db} do
    previous = Application.get_env(:agent_board, :live_poll_interval)
    Application.put_env(:agent_board, :live_poll_interval, 10)
    on_exit(fn -> Application.put_env(:agent_board, :live_poll_interval, previous) end)

    state = AgentBoard.Live.handle_info(:poll, %{})

    assert {:noreply, %{}} = state
    assert_receive :poll, 11_000
  end

  test "a missing state database does not crash the poller", %{db: _db} do
    previous = Application.get_env(:agent_board, :state_db)
    Application.put_env(:agent_board, :state_db, "/does/not/exist.sqlite")
    on_exit(fn -> Application.put_env(:agent_board, :state_db, previous) end)

    repo = isolated_repo()

    assert is_map(AgentBoard.Live.poll(%{}))
    assert Repo.get_by(Task, repository_id: repo.id) == nil
  end
end
