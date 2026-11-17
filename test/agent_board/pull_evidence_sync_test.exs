defmodule AgentBoard.PullEvidenceSyncTest do
  use AgentBoard.DataCase, async: false
  alias AgentBoard.{Board, Repo, Sync}
  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Sync.PullEvidence
  @stub __MODULE__.Stub
  @sha String.duplicate("a1", 20)

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)
    {:ok, repo} = Board.add_repository("example", "project")
    client = Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)
    %{repo: repo, client: client}
  end

  test "automatic sync paginates receipts, caches them, broadcasts, and notices deleted evidence",
       %{repo: repo, client: client} do
    Board.subscribe(repo.id)
    stub(self(), "2026-11-17T12:00:00Z", [comment()])
    assert :ok = Sync.sync_repo(client, repo)
    assert_receive :board_updated
    assert_receive {:comments, "1"}
    assert_receive {:comments, "2"}
    pull = Repo.get_by!(PullRequest, repository_id: repo.id, number: 42)
    assert pull.reported_evidence["ci"]["result"] == "pass"

    assert pull.reported_evidence["ci"]["url"] ==
             "https://github.com/example/project/pull/42#issuecomment-3"

    assert pull.review_state == "none"
    assert pull.checks_state == "none"
    assert pull.evidence_refresh_at == nil
    assert :ok = Sync.sync_repo(client, repo)
    refute_receive {:comments, _}
    stub(self(), "2026-11-17T13:00:00Z", [])
    assert :ok = Sync.sync_repo(client, repo)
    assert_receive {:comments, "1"}
    assert Repo.get!(PullRequest, pull.id).reported_evidence == %{}
  end

  test "failed read retains evidence and defers retry", %{repo: repo, client: client} do
    pull = insert_pull(repo, 42, %{"ci" => %{"result" => "pass"}})
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 502, "unavailable") end)
    PullEvidence.refresh_one(client, repo)
    saved = Repo.get!(PullRequest, pull.id)
    assert saved.reported_evidence == pull.reported_evidence
    assert DateTime.diff(saved.evidence_refresh_at, DateTime.utc_now()) > 3500
  end

  test "reads only one candidate each cycle", %{repo: repo, client: client} do
    insert_pull(repo, 42)
    insert_pull(repo, 43)
    parent = self()

    Req.Test.stub(@stub, fn conn ->
      send(parent, :read)
      Req.Test.json(conn, [])
    end)

    PullEvidence.refresh_one(client, repo)
    assert_receive :read
    refute_receive :read
    PullEvidence.refresh_one(client, repo)
    assert_receive :read
    refute_receive :read
  end

  defp stub(parent, updated, comments) do
    Req.Test.stub(@stub, fn conn ->
      case conn.request_path do
        "/repos/example/project/pulls" ->
          Req.Test.json(conn, [
            %{
              "number" => 42,
              "title" => "Improve choices",
              "state" => "closed",
              "merged_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
              "updated_at" => updated,
              "head" => %{"sha" => @sha}
            }
          ])

        "/repos/example/project/issues/42/comments" ->
          conn = Plug.Conn.fetch_query_params(conn)
          page = conn.query_params["page"]
          send(parent, {:comments, page})

          comment_page(conn, page, comments)

        "/repos/example/project/commits/" <> _ ->
          Req.Test.json(conn, %{"check_runs" => []})

        _ ->
          Req.Test.json(conn, [])
      end
    end)
  end

  defp comment_page(conn, page, comments) do
    if page == "1" and comments != [] do
      conn
      |> Plug.Conn.put_resp_header(
        "link",
        "<https://api.github.com/repos/example/project/issues/42/comments?page=2>; rel=\"next\""
      )
      |> Req.Test.json([])
    else
      Req.Test.json(conn, comments)
    end
  end

  defp insert_pull(repo, n, evidence \\ %{}) do
    Repo.insert!(%PullRequest{
      repository_id: repo.id,
      number: n,
      state: "merged",
      title: "Task",
      head_sha: @sha,
      merged_at: DateTime.utc_now() |> DateTime.truncate(:second),
      reported_evidence: evidence,
      evidence_refresh_at: DateTime.add(DateTime.utc_now(), -60) |> DateTime.truncate(:second)
    })
  end

  defp comment,
    do: %{
      "id" => 3,
      "author_association" => "OWNER",
      "user" => %{"login" => "maintainer"},
      "body" => "### Validation\n- `make test`: passed em #{@sha}",
      "updated_at" => "2026-11-17T12:00:00Z"
    }
end
