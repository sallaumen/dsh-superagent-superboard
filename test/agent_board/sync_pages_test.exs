defmodule AgentBoard.SyncPagesTest do
  @moduledoc "Issues and pulls are read past the first page: nothing updated since the last sync is skipped."
  use AgentBoard.DataCase, async: false

  import Ecto.Query

  alias AgentBoard.{Board, Repo, Sync}
  alias AgentBoard.Board.{PullRequest, Task}

  @stub AgentBoard.SyncPagesTest.Stub
  @next ~s(<https://api.github.com/x?page=2>; rel="next")

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    %{repo: repo}
  end

  defp client,
    do: Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)

  defp issue(number) do
    %{
      "number" => number,
      "title" => "Issue #{number}",
      "state" => "open",
      "html_url" => "https://github.com/sallaumen/arena-rogue/issues/#{number}",
      "user" => %{"login" => "sallaumen"},
      "updated_at" => "2026-11-04T00:00:00Z"
    }
  end

  defp pull(number, updated_at) do
    %{
      "number" => number,
      "title" => "PR #{number}",
      "state" => "open",
      "html_url" => "https://github.com/sallaumen/arena-rogue/pull/#{number}",
      "user" => %{"login" => "sallaumen"},
      "updated_at" => updated_at,
      "head" => %{"sha" => "sha#{number}"}
    }
  end

  defp next_page(conn), do: Plug.Conn.put_resp_header(conn, "link", @next)

  defp stub(fun) do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      send(test_pid, {:read, conn.request_path, conn.query_params})

      if String.ends_with?(conn.request_path, "/check-runs"),
        do: Req.Test.json(conn, %{"check_runs" => []}),
        else: fun.(conn)
    end)
  end

  defp reads(path), do: reads(path, [])

  defp reads(path, acc) do
    receive do
      {:read, ^path, params} -> reads(path, [params | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp numbers(schema),
    do: Repo.all(from r in schema, select: r.number, order_by: r.number)

  test "every page of issues updated since the last sync is read, and since is sent", %{
    repo: repo
  } do
    Board.log_event(repo.id, "sync", "sallaumen/arena-rogue", %{})

    stub(fn conn ->
      case {conn.request_path, conn.query_params["page"]} do
        {"/repos/sallaumen/arena-rogue/issues", "1"} ->
          conn |> next_page() |> Req.Test.json(Enum.map(1..100, &issue/1))

        {"/repos/sallaumen/arena-rogue/issues", "2"} ->
          Req.Test.json(conn, [issue(101)])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    assert [first, second] = reads("/repos/sallaumen/arena-rogue/issues")
    assert {:ok, since, 0} = DateTime.from_iso8601(first["since"])
    assert DateTime.compare(since, DateTime.utc_now()) == :lt
    assert second["since"] == first["since"]
    assert numbers(Task) == Enum.to_list(1..101)
  end

  test "pulls keep paging while the page ends newer than the last sync", %{repo: repo} do
    Board.log_event(repo.id, "sync", "sallaumen/arena-rogue", %{})
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    stub(fn conn ->
      case {conn.request_path, conn.query_params["page"]} do
        {"/repos/sallaumen/arena-rogue/pulls", "1"} ->
          conn |> next_page() |> Req.Test.json([pull(1, now)])

        {"/repos/sallaumen/arena-rogue/pulls", "2"} ->
          Req.Test.json(conn, [pull(2, now)])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    assert [_page1, _page2] = reads("/repos/sallaumen/arena-rogue/pulls")
    assert numbers(PullRequest) == [1, 2]
  end

  test "pulls stop paging at the first page that ends older than the last sync", %{repo: repo} do
    Board.log_event(repo.id, "sync", "sallaumen/arena-rogue", %{})

    stub(fn conn ->
      case {conn.request_path, conn.query_params["page"]} do
        {"/repos/sallaumen/arena-rogue/pulls", "1"} ->
          conn
          |> next_page()
          |> Req.Test.json([
            pull(1, DateTime.to_iso8601(DateTime.utc_now())),
            pull(2, "2020-01-01T00:00:00Z")
          ])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    assert [_page1] = reads("/repos/sallaumen/arena-rogue/pulls")
    assert numbers(PullRequest) == [1, 2]
  end

  test "the first import reads every page, up to ten, without since", %{repo: repo} do
    stub(fn conn ->
      page = String.to_integer(conn.query_params["page"] || "1")

      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" ->
          conn |> next_page() |> Req.Test.json([issue(page)])

        "/repos/sallaumen/arena-rogue/pulls" ->
          conn |> next_page() |> Req.Test.json([pull(page, "2020-01-01T00:00:00Z")])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    issue_reads = reads("/repos/sallaumen/arena-rogue/issues")
    assert length(issue_reads) == 10
    refute Enum.any?(issue_reads, &Map.has_key?(&1, "since"))
    assert length(reads("/repos/sallaumen/arena-rogue/pulls")) == 10
    assert numbers(Task) == Enum.to_list(1..10)
  end
end
