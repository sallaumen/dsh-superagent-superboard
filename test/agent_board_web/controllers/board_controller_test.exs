defmodule AgentBoardWeb.BoardControllerTest do
  @moduledoc "The JSON API the board and the scripts speak."
  use AgentBoardWeb.ConnCase, async: true

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  @repo_path "/api/repos"
  @board_path "/api/board"

  test "GET /api/repos lists the tracked repositories", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    conn = get(conn, @repo_path)
    assert %{"owner" => "sallaumen", "name" => "arena-rogue"} = hd(json_response(conn, 200))
  end

  test "POST /api/repos tracks a repository", %{conn: conn} do
    conn = post(conn, @repo_path, %{owner: "sallaumen", name: "o_colmex"})

    assert %{"owner" => "sallaumen", "name" => "o_colmex"} = json_response(conn, 201)
  end

  test "POST /api/repos rejects a name with a slash", %{conn: conn} do
    conn = post(conn, @repo_path, %{owner: "sallaumen", name: "a/b"})

    assert %{"error" => _} = json_response(conn, 400)
  end

  test "GET /api/board returns the board for a tracked repository", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    task(repo, 1, "First task", "queued")

    conn = get(conn, @board_path <> "?repo=sallaumen/arena-rogue")
    body = json_response(conn, 200)

    assert [%{"title" => "First task"}] = body["queued"]
  end

  test "GET /api/board is 404 for an untracked repository", %{conn: conn} do
    conn = get(conn, @board_path <> "?repo=nobody/nothing")

    assert %{"error" => _} = json_response(conn, 404)
  end

  test "PATCH /api/tasks archives a task", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    t = task(repo, 2, "Archive me", "queued")

    conn = patch(conn, "/api/tasks/#{t.id}", %{action: "archive"})

    assert %{"ok" => true} = json_response(conn, 200)
    assert Repo.get(Task, t.id).archived
  end

  test "PATCH /api/tasks is 404 for an unknown task", %{conn: conn} do
    conn = patch(conn, "/api/tasks/999999", %{action: "archive"})

    assert %{"error" => _} = json_response(conn, 404)
  end

  defp task(repo, number, title, state) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: number,
      title: title,
      state: state
    })
    |> Repo.insert!()
  end
end
