defmodule AgentBoard.SyncRepoTest do
  @moduledoc "The sync against a fake GitHub: no network, the real code paths."
  use AgentBoard.DataCase, async: false

  import Ecto.Query

  alias AgentBoard.{Board, Repo, Sync}
  alias AgentBoard.Board.Task

  @stub AgentBoard.SyncRepoTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    %{repo: repo}
  end

  defp client,
    do: Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)

  defp issue(number, state) do
    %{
      "number" => number,
      "title" => "Issue #{number}",
      "state" => state,
      "html_url" => "https://github.com/sallaumen/arena-rogue/issues/#{number}",
      "user" => %{"login" => "sallaumen"},
      "created_at" => "2026-11-04T00:00:00Z"
    }
  end

  defp stub_github(fn_path) do
    Req.Test.stub(@stub, fn conn -> fn_path.(conn) end)
  end

  test "an open issue becomes a queued task", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" -> Req.Test.json(conn, [issue(7, "open")])
        _ -> Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    assert %Task{state: "queued", title: "Issue 7"} =
             Repo.one(from t in Task, where: t.number == 7)
  end

  test "the sync event summarises the error count", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" ->
          Req.Test.json(conn, [issue(9, "open") |> Map.put("title", nil)])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    sync = Enum.find(Board.events(repo), &(&1.kind == "sync"))
    assert sync.payload["errors"] == 1
  end

  test "an invalid issue is logged, not swallowed", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" ->
          Req.Test.json(conn, [issue(9, "open") |> Map.put("title", nil)])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok
    assert Enum.any?(Board.events(repo), &(&1.kind == "issue_error"))
  end

  test "a broken review does not kill the sync", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/pulls" ->
          Req.Test.json(conn, [
            %{
              "number" => 9,
              "title" => "A PR",
              "state" => "open",
              "html_url" => "https://github.com/x/y/pull/9",
              "user" => %{"login" => "sallaumen"},
              "created_at" => "2026-11-04T00:00:00Z",
              "head" => %{"sha" => "abc"}
            }
          ])

        "/repos/sallaumen/arena-rogue/pulls/9/reviews" ->
          Plug.Conn.send_resp(conn, 500, "boom")

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok
    assert Enum.any?(Board.events(repo), &(&1.kind == "pull_error"))
  end

  test "a broken conversation does not kill the sync", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" -> Req.Test.json(conn, [issue(7, "open")])
        "/repos/sallaumen/arena-rogue/issues/7/comments" -> Plug.Conn.send_resp(conn, 500, "boom")
        _ -> Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    task = Repo.one(from t in Task, where: t.number == 7)
    assert task.state == "queued"
    assert Enum.any?(Board.events(repo), &(&1.kind == "comment_error"))
  end

  test "the sync pulls the comments of the active tasks", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" ->
          Req.Test.json(conn, [issue(7, "open")])

        "/repos/sallaumen/arena-rogue/issues/7/comments" ->
          Req.Test.json(conn, [
            %{"id" => 101, "user" => %{"login" => "sallaumen-agent"}, "body" => "On it."},
            %{"id" => 102, "user" => %{"login" => "sallaumen"}, "body" => "Any progress?"}
          ])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    task = Repo.one(from t in Task, where: t.number == 7)
    comments = Board.comments(task)

    assert Enum.map(comments, & &1.kind) == ["agent", "user"]
    assert Enum.map(comments, & &1.body) == ["On it.", "Any progress?"]
  end

  test "a GitHub failure is logged and returned, not raised", %{repo: repo} do
    stub_github(fn conn ->
      Plug.Conn.send_resp(conn, 500, "boom")
    end)

    assert {:error, exception} = Sync.sync_repo(client(), repo)
    assert Exception.message(exception) =~ "500"

    assert Enum.any?(Board.events(repo), &(&1.kind == "sync_error"))
  end

  test "a rate limit is reported with the retry-after value", %{repo: repo} do
    stub_github(fn conn ->
      conn
      |> Plug.Conn.put_resp_header("retry-after", "17")
      |> Plug.Conn.send_resp(429, "slow down")
    end)

    assert {:error, exception} = Sync.sync_repo(client(), repo)
    assert Exception.message(exception) =~ "retry after 17s"
  end

  test "all/1 syncs every active repository with the given client", %{repo: _repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" -> Req.Test.json(conn, [issue(11, "open")])
        _ -> Req.Test.json(conn, [])
      end
    end)

    assert Sync.all(client()) == 1
    assert %Task{state: "queued"} = Repo.one(from t in Task, where: t.number == 11)
  end

  test "a closed issue becomes a done task", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" -> Req.Test.json(conn, [issue(8, "closed")])
        _ -> Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok
    assert %Task{state: "done"} = Repo.one(from t in Task, where: t.number == 8)
  end

  test "a pull request becomes a merged task with its rollups", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/pulls" ->
          Req.Test.json(conn, [
            %{
              "number" => 9,
              "title" => "A PR",
              "state" => "closed",
              "merged_at" => "2026-11-04T00:00:00Z",
              "html_url" => "https://github.com/sallaumen/arena-rogue/pull/9",
              "user" => %{"login" => "sallaumen"},
              "created_at" => "2026-11-04T00:00:00Z",
              "head" => %{"sha" => "abc"}
            }
          ])

        path when is_binary(path) ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    assert %AgentBoard.Board.PullRequest{number: 9} =
             Repo.one(from p in AgentBoard.Board.PullRequest, where: p.number == 9)
  end
end
