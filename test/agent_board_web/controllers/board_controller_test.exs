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

  test "POST /api/tasks creates a task through the injected client", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    previous = Application.get_env(:agent_board, :github_client)
    on_exit(fn -> Application.put_env(:agent_board, :github_client, previous) end)

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(
        base_url: "https://api.github.com",
        plug: {Req.Test, AgentBoardWeb.BoardControllerTest.Stub},
        retry: false
      )
    end)

    Req.Test.stub(AgentBoardWeb.BoardControllerTest.Stub, fn conn ->
      Req.Test.json(conn, %{"number" => 55, "html_url" => "https://github.com/x/y/issues/55"})
    end)

    params = %{repo: "sallaumen/arena-rogue", title: "From the API", body: "hi"}

    # Creating is red: the first call runs nothing and answers the sentence.
    first = post(conn, "/api/tasks", params)

    assert %{"error" => "confirmation_required", "confirm" => phrase} = json_response(first, 428)

    assert phrase ==
             "Criar no arena-rogue a tarefa “From the API”? " <>
               "O board abre a issue no GitHub e o agente começa sozinho."

    assert Repo.aggregate(Task, :count, :id) == 0

    # Sending the sentence back is the confirmation.
    conn = post(build_conn(), "/api/tasks", Map.put(params, :confirm, phrase))
    assert %{"number" => 55, "outcome" => "created"} = json_response(conn, 201)

    assert [%{decision: "confirmed", via: "api"}, %{decision: "refused", detail: "unconfirmed"}] =
             AgentBoard.Actions.recent(2)
  end

  test "POST /api/tasks names the executor, and an unknown one is a 400", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    test_pid = self()

    previous = Application.get_env(:agent_board, :github_client)
    on_exit(fn -> Application.put_env(:agent_board, :github_client, previous) end)

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(
        base_url: "https://api.github.com",
        plug: {Req.Test, AgentBoardWeb.BoardControllerTest.Stub},
        retry: false
      )
    end)

    Req.Test.stub(AgentBoardWeb.BoardControllerTest.Stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:issue, Jason.decode!(body)})
      Req.Test.json(conn, %{"number" => 56, "html_url" => "https://github.com/x/y/issues/56"})
    end)

    # A real API request has no interface language (the test process is pinned
    # to pt-BR by ConnCase, which would hide a reason stored in English).
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")

    params = %{repo: "sallaumen/arena-rogue", title: "Placar", body: "hi", executor: "codex"}
    first = post(conn, "/api/tasks", params)
    assert %{"confirm" => phrase} = json_response(first, 428)
    assert phrase =~ "para o Codex"

    conn = post(build_conn(), "/api/tasks", Map.put(params, :confirm, phrase))
    assert %{"number" => 56} = json_response(conn, 201)

    assert_received {:issue, %{"labels" => ["executor:codex"], "body" => "hi"}}
    task = Repo.get_by!(Task, repository_id: repo.id, number: 56)

    assert %AgentBoard.Routing.Decision{chosen: "codex", decided_by: "api", reasons: reasons} =
             Repo.get_by!(AgentBoard.Routing.Decision, task_id: task.id)

    assert "Você pediu o Codex." in reasons

    bad = post(build_conn(), "/api/tasks", %{params | executor: "gpt"})
    assert %{"error" => error} = json_response(bad, 400)
    assert error =~ "executor"
  end

  test "POST /api/tasks with a sentence for other values is refused", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    conn =
      post(conn, "/api/tasks", %{
        repo: "sallaumen/arena-rogue",
        title: "Other title",
        confirm: "Criar no arena-rogue a tarefa “From the API”? Pode."
      })

    assert %{"error" => "confirmation_mismatch", "confirm" => phrase} = json_response(conn, 428)
    assert phrase =~ "“Other title”"
    assert Repo.aggregate(Task, :count, :id) == 0
  end

  test "PATCH /api/tasks of an unknown id is 404", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    conn = patch(conn, "/api/tasks/999999", %{action: "archive"})

    assert json_response(conn, 404)
  end

  test "PATCH /api/tasks archives a task", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    t = task(repo, 2, "Archive me", "queued")

    conn = patch(conn, "/api/tasks/#{t.id}", %{action: "archive"})

    assert %{"ok" => true} = json_response(conn, 200)
    assert Repo.get(Task, t.id).archived
  end

  test "PATCH /api/tasks stop with a failing GitHub is not a 500", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    t = task(repo, 3, "Stop me", "queued")

    Req.Test.stub(AgentBoard.BoardControllerTest.Stub, fn conn ->
      Plug.Conn.send_resp(conn, 500, "boom")
    end)

    phrase = AgentBoard.Actions.phrase(:stop_task, %{task: t})
    conn = patch(conn, "/api/tasks/#{t.id}", %{action: "stop", confirm: phrase})

    assert json_response(conn, 404)
  end

  test "PATCH /api/tasks resumes an archived task", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    t = task(repo, 3, "Resume me", "queued")
    {:ok, _} = Board.archive_task(t)

    conn = patch(conn, "/api/tasks/#{t.id}", %{action: "resume"})

    assert %{"ok" => true} = json_response(conn, 200)
    refute Repo.get(Task, t.id).archived
  end

  test "PATCH /api/tasks stops a task through the injected client", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    t = task(repo, 4, "Stop me", "queued")

    previous = Application.get_env(:agent_board, :github_client)
    on_exit(fn -> Application.put_env(:agent_board, :github_client, previous) end)

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(
        base_url: "https://api.github.com",
        plug: {Req.Test, AgentBoardWeb.BoardControllerTest.Stub2},
        retry: false
      )
    end)

    Req.Test.stub(AgentBoardWeb.BoardControllerTest.Stub2, fn conn ->
      Req.Test.json(conn, %{"state" => "closed"})
    end)

    first = patch(conn, "/api/tasks/#{t.id}", %{action: "stop"})
    assert %{"confirm" => phrase} = json_response(first, 428)
    refute Repo.get(Task, t.id).stopped

    conn = patch(build_conn(), "/api/tasks/#{t.id}", %{action: "stop", confirm: phrase})

    assert %{"ok" => true} = json_response(conn, 200)
    assert Repo.get(Task, t.id).stopped
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

  describe "a body in another shape" do
    test "a map where a slug goes answers 404 on the board", %{conn: conn} do
      assert json_response(get(conn, "/api/board", %{"repo" => %{"a" => "b"}}), 404)
    end

    test "a map where text goes is refused", %{conn: conn} do
      {:ok, _repo} = AgentBoard.Board.add_repository("fixture", "shapes")

      for params <- [
            %{"repo" => %{"a" => 1}, "title" => "x"},
            %{"repo" => "fixture/shapes", "title" => ["x"]}
          ] do
        assert_error_sent 400, fn -> post(conn, "/api/tasks", params) end
      end

      assert json_response(
               post(conn, "/api/tasks", %{
                 "repo" => "fixture/shapes",
                 "title" => "x",
                 "body" => %{"a" => 1}
               }),
               400
             )

      assert_error_sent 400, fn -> post(conn, "/api/repos", %{"owner" => %{}, "name" => "x"}) end
    end
  end
end
