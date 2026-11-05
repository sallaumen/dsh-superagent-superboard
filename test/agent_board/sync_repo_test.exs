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

  test "a GitHub failure is logged and returned, not raised", %{repo: repo} do
    stub_github(fn conn ->
      Plug.Conn.send_resp(conn, 500, "boom")
    end)

    assert {:error, exception} = Sync.sync_repo(client(), repo)
    assert Exception.message(exception) =~ "500"

    assert Enum.any?(Board.events(repo), &(&1.kind == "sync_error"))
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
