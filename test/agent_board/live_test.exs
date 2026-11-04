defmodule AgentBoard.LiveTest do
  @moduledoc "The live poller: the ticket overlay in real time."
  use AgentBoard.DataCase, async: false

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  @sqlite "create table ticket (value text);"

  @running ~s({"mandate":{"basis":{"scope":{"number":42}}},"assignments":[{"state":"running"}]})
  @stopped ~s({"mandate":{"basis":{"scope":{"number":42}}},"assignments":[{"state":"running"}],"stopped":true})

  setup do
    previous = Application.get_env(:agent_board, :state_db)
    path = Path.join(System.tmp_dir!(), "live-test-#{System.unique_integer([:positive])}.sqlite")
    {:ok, db} = Exqlite.Sqlite3.open(path)
    :ok = Exqlite.Sqlite3.execute(db, @sqlite)
    Application.put_env(:agent_board, :state_db, path)

    on_exit(fn ->
      Exqlite.Sqlite3.close(db)
      File.rm(path)
      if previous, do: Application.put_env(:agent_board, :state_db, previous)
    end)

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
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    t = task(repo)

    :ok = Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('" <> @running <> "')")

    Board.subscribe(repo.id)
    AgentBoard.Live.poll(%{})

    assert_receive :board_updated
    assert Repo.get(Task, t.id).state == "running"
  end

  test "a second poll with the same tickets does not broadcast again", %{db: db} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    :ok = Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('" <> @running <> "')")

    Board.subscribe(repo.id)

    state = AgentBoard.Live.poll(%{})
    assert_receive :board_updated

    _state = AgentBoard.Live.poll(state)
    refute_receive :board_updated, 150
  end

  test "a stopped ticket is not overlaid", %{db: db} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    t = task(repo)

    :ok = Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('" <> @stopped <> "')")

    AgentBoard.Live.poll(%{})

    assert Repo.get(Task, t.id).state == "queued"
  end
end
