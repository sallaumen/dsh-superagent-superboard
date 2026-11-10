defmodule AgentBoardWeb.BoardStallTest do
  @moduledoc "A running ticket that went silent is shown as such, from the runner's own timestamps."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  # One assignment started long ago, no report, no worktree: the only signal
  # is the start, older than any threshold.
  @silent ~s({"mandate":{"basis":{"scope":{"number":42}}},"assignments":[{"state":"running","startedAt":"2026-11-06T10:00:00.000Z","idleAt":null}],"execution":{"directory":"/does/not/exist"}})

  # The state database is a global knob, so this module is not async: the
  # async modules have all finished when it runs.
  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "board-stall-#{System.pid()}-#{System.unique_integer([:positive])}.sqlite"
      )

    File.rm(path)
    previous = Application.get_env(:agent_board, :state_db)
    {:ok, db} = Exqlite.Sqlite3.open(path)
    :ok = Exqlite.Sqlite3.execute(db, "create table ticket (value text);")
    :ok = Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('" <> @silent <> "')")
    Exqlite.Sqlite3.close(db)
    Application.put_env(:agent_board, :state_db, path)

    on_exit(fn ->
      for suffix <- ["", "-wal", "-shm"], do: File.rm(path <> suffix)

      if previous,
        do: Application.put_env(:agent_board, :state_db, previous),
        else: Application.delete_env(:agent_board, :state_db)
    end)

    :ok
  end

  # The worker said it was waiting at 10:05 and read the owner's answer at 10:50.
  @answered ~s({"mandate":{"basis":{"scope":{"number":77}}},"assignments":[{"id":"a1","state":"running","startedAt":"2026-11-06T10:00:00.000Z","idleAt":"2026-11-06T10:05:00.000Z","report":{"state":"waiting","summary":"Sem creditos.","at":"2026-11-06T10:05:00.000Z"}}],"inputs":[{"kind":"trigger","human":true,"readAt":"2026-11-06T10:50:00.000Z","deliveredTo":"a1"}],"execution":{"directory":"/does/not/exist"}})

  test "a task back at work after the owner's answer says so in Agora", %{conn: conn} do
    {:ok, db} = Exqlite.Sqlite3.open(Application.get_env(:agent_board, :state_db))
    :ok = Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('" <> @answered <> "')")
    Exqlite.Sqlite3.close(db)

    {:ok, repo} = Board.add_repository("fixture", "answered")
    Board.log_event(repo.id, "sync", "fixture/answered", %{"errors" => 0})

    answered =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 77,
        title: "Answered run",
        state: "running"
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/answered")

    assert has_element?(
             view,
             "#sec-now #task-#{answered.id} .ab-run__answered",
             "De volta ao trabalho: leu sua resposta às 10:50"
           )

    # The fixture's clock is days old, so the run is also silent: that is the
    # only thing it asks of the owner, counted from the answer, not a block.
    assert has_element?(view, "#sec-needs #silence-#{answered.id}", "Sem sinal há")
    refute has_element?(view, "#sec-needs", "Bloqueado")
  end

  test "a silent run is marked in Agora and lands in Precisa de você", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "stall")
    Board.log_event(repo.id, "sync", "fixture/stall", %{"errors" => 0})

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 42,
        title: "Quiet run",
        state: "running"
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/stall")

    assert has_element?(
             view,
             "#sec-now #task-#{task.id}.is-stalled .ab-run__silence",
             "sem sinal há"
           )

    # no change in the worktree since the start: still the first stage
    assert has_element?(view, "#sec-now #task-#{task.id} .ab-phase.is-now", "Análise")
    assert has_element?(view, ~s(#task-#{task.id}[aria-label$="Etapa: Análise"]))
    assert has_element?(view, "#sec-now #task-#{task.id} .ab-phase:not(.is-now)", "PR")

    refute has_element?(view, "#sec-now #task-#{task.id} .ab-g.is-live")
    assert has_element?(view, "#sec-needs #silence-#{task.id}", "Sem sinal há")
    assert has_element?(view, "#sec-needs #silence-#{task.id}", "Começou às")
    assert has_element?(view, "#sec-needs #silence-#{task.id} button", "Ver detalhe")

    # one task, two items, two ids: the page stays valid
    assert length(Regex.scan(~r/id="task-#{task.id}"/, render(view))) == 1
  end
end
