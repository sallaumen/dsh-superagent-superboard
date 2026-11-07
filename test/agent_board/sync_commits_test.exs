defmodule AgentBoard.SyncCommitsTest do
  @moduledoc "The default branch's commits: stored once, paged, and never the whole sync's failure."
  use AgentBoard.DataCase, async: false

  import Ecto.Query

  alias AgentBoard.{Board, Repo, Sync}
  alias AgentBoard.Board.{Commit, Event}

  @stub AgentBoard.SyncCommitsTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    %{repo: repo}
  end

  defp client,
    do: Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)

  defp commit(sha, at, message \\ "Add a thing\n\nBody") do
    %{
      "sha" => sha,
      "commit" => %{
        "message" => message,
        "author" => %{"name" => "Lucas", "date" => at},
        "committer" => %{"name" => "GitHub", "date" => at}
      },
      "author" => %{"login" => "sallaumen-agent"}
    }
  end

  defp stub(fun), do: Req.Test.stub(@stub, fn conn -> fun.(conn) end)

  test "commits are stored once, by sha, with their landing time", %{repo: repo} do
    stub(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/commits" ->
          Req.Test.json(conn, [
            commit("aaa", "2026-11-07T01:08:16Z"),
            commit("bbb", "2026-11-07T00:05:10Z", "Fix\nmore")
          ])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert :ok = Sync.sync_repo(client(), repo)
    assert :ok = Sync.sync_repo(client(), repo)

    commits = Repo.all(from c in Commit, where: c.repository_id == ^repo.id, order_by: c.sha)
    assert Enum.map(commits, & &1.sha) == ["aaa", "bbb"]
    assert hd(commits).committed_at == ~U[2026-11-07 01:08:16Z]
    assert hd(commits).author == "sallaumen-agent"
    assert hd(commits).message == "Add a thing"

    sync = Board.latest_sync(repo)
    assert sync.kind == "sync"
    assert sync.payload["commits"] == 0
  end

  test "the second read continues from the newest commit stored", %{repo: repo} do
    test_pid = self()

    stub(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/commits" ->
          send(test_pid, {:since, conn.query_params["since"]})
          Req.Test.json(conn, [commit("aaa", "2026-11-07T01:08:16Z")])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    Sync.sync_repo(client(), repo)
    assert_receive {:since, first}
    assert {:ok, first_at, _} = DateTime.from_iso8601(first)
    assert DateTime.diff(DateTime.utc_now(), first_at, :day) in 6..7

    Sync.sync_repo(client(), repo)
    assert_receive {:since, "2026-11-07T01:08:16Z"}
  end

  test "a Link header with rel=next reads the next page", %{repo: repo} do
    stub(fn conn ->
      case {conn.request_path, conn.query_params["page"]} do
        {"/repos/sallaumen/arena-rogue/commits", "1"} ->
          conn
          |> Plug.Conn.put_resp_header(
            "link",
            ~s(<https://api.github.com/x?page=2>; rel="next", <https://api.github.com/x?page=2>; rel="last")
          )
          |> Req.Test.json([commit("aaa", "2026-11-07T01:08:16Z")])

        {"/repos/sallaumen/arena-rogue/commits", "2"} ->
          Req.Test.json(conn, [commit("bbb", "2026-11-07T00:08:16Z")])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    Sync.sync_repo(client(), repo)

    assert Repo.aggregate(from(c in Commit, where: c.repository_id == ^repo.id), :count) == 2
    assert Board.latest_sync(repo).payload["commits"] == 2
  end

  test "a failing commit read is one event; issues and pulls still sync", %{repo: repo} do
    stub(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/commits" ->
          Plug.Conn.send_resp(conn, 500, "boom")

        "/repos/sallaumen/arena-rogue/issues" ->
          Req.Test.json(conn, [
            %{
              "number" => 7,
              "title" => "Issue 7",
              "state" => "open",
              "html_url" => "https://github.com/sallaumen/arena-rogue/issues/7",
              "user" => %{"login" => "sallaumen"}
            }
          ])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert :ok = Sync.sync_repo(client(), repo)

    assert Repo.exists?(from t in AgentBoard.Board.Task, where: t.number == 7)
    assert Repo.exists?(from e in Event, where: e.kind == "commit_error")

    sync = Board.latest_sync(repo)
    refute Map.has_key?(sync.payload, "commits")
    assert sync.payload["errors"] == 1
  end
end
