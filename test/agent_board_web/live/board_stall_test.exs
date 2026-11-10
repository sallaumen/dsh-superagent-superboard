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
