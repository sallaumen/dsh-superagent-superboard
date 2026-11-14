defmodule AgentBoard.Sync.MergedPullTest do
  use AgentBoardWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query
  use Oban.Testing, repo: AgentBoard.Repo

  alias AgentBoard.{AgentState, Board, Repo}
  alias AgentBoard.Board.{PullRequest, Repository, Task}
  alias AgentBoard.Sync.MergedPull

  setup do
    repo = Repo.insert!(Repository.changeset(%Repository{}, %{owner: "owner", name: "board"}))
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    previous = Application.get_env(:agent_board, :github_client)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :github_client, previous),
        else: Application.delete_env(:agent_board, :github_client)
    end)

    %{repo: repo, at: now}
  end

  defp ticket(at) do
    own = fn n, time ->
      %{
        "thread" => "github:#{n}",
        "own" => true,
        "closed" => %{"outcome" => "merged", "at" => time}
      }
    end

    %{
      "channels" => [
        %{"address" => %{"url" => "https://github.com/owner/board/issues/697", "number" => 697}}
      ],
      "ended" => %{"outcome" => "merged", "at" => at},
      "follows" => [
        own.(700, at),
        own.(697, at),
        own.(688, "2020-01-01T00:00:00Z"),
        Map.put(own.(701, at), "own", false)
      ]
    }
  end

  defp stub(fun) do
    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(base_url: "https://api.github.test", plug: fun, retry: false)
    end)
  end

  defp pull(at),
    do: %{
      "number" => 700,
      "state" => "closed",
      "title" => "Document the recovery",
      "body" => "Closes #697",
      "html_url" => "https://github.com/owner/board/pull/700",
      "merged_at" => at,
      "base" => %{"repo" => %{"full_name" => "Owner/Board"}},
      "head" => %{"sha" => "abc"}
    }

  test "ticket poll enqueues one exact PR, persists history and notifies an open board", %{
    conn: conn,
    repo: repo,
    at: at
  } do
    path = Path.join(System.tmp_dir!(), "merge-poll-#{System.unique_integer([:positive])}.sqlite")
    previous = Application.fetch_env!(:agent_board, :state_db)
    {:ok, db} = Exqlite.Sqlite3.open(path)

    on_exit(fn ->
      Exqlite.Sqlite3.close(db)
      File.rm(path)
      Application.put_env(:agent_board, :state_db, previous)
    end)

    raw = Jason.encode!(ticket(at))

    :ok =
      Exqlite.Sqlite3.execute(
        db,
        "CREATE TABLE ticket (value TEXT); INSERT INTO ticket VALUES ('#{raw}')"
      )

    Application.put_env(:agent_board, :state_db, path)

    stub(fn conn ->
      case conn.request_path do
        "/repos/owner/board/pulls/700" -> Req.Test.json(conn, pull(at))
        "/repos/owner/board/pulls/700/reviews" -> Req.Test.json(conn, [])
        "/repos/owner/board/commits/abc/check-runs" -> Req.Test.json(conn, %{check_runs: []})
        other -> flunk("Unexpected GitHub read: #{other}")
      end
    end)

    state = AgentBoard.TicketPoller.poll()
    AgentBoard.TicketPoller.poll(state)
    AgentBoard.TicketPoller.poll()
    assert [job] = all_enqueued(worker: MergedPull)

    assert Repo.exists?(
             from d in AgentBoard.Actions.Decision,
               where:
                 d.action == "sync_merged_pull" and d.subject == "owner/board#700" and
                   d.outcome == "ok"
           )

    assert job.args == %{"repo_id" => repo.id, "number" => 700}
    {:ok, view, _} = live(conn, ~p"/?repo=owner/board")
    selector = ~s(#sec-log button[phx-value-number="700"])
    refute has_element?(view, selector)
    Board.subscribe(repo.id)
    assert :ok = MergedPull.perform(job)
    assert_receive :board_updated
    assert has_element?(view, selector, "Document the recovery")
    assert {:ok, %{merged: [%{number: 700, state: "merged"}]}} = Board.board("owner/board")
    stub(fn _ -> flunk("Duplicate job re-read GitHub") end)
    assert :ok = MergedPull.perform(job)
    refute_received :board_updated
  end

  test "open, unrelated and invalid responses cannot create history or close a reopened issue", %{
    repo: repo,
    at: at
  } do
    task =
      Repo.insert!(
        Task.changeset(%Task{}, %{
          repository_id: repo.id,
          kind: "issue",
          number: 697,
          title: "Rework",
          state: "queued"
        })
      )

    job = %Oban.Job{args: %{"number" => 700, "repo_id" => repo.id}}

    for override <- [
          %{"state" => "open"},
          %{"merged_at" => nil},
          %{"merged_at" => "invalid"},
          %{"number" => 701},
          %{"base" => %{"repo" => %{"full_name" => "owner/another"}}}
        ] do
      stub(&Req.Test.json(&1, Map.merge(pull(at), override)))
      assert :ok = MergedPull.perform(job)
      refute Repo.exists?(PullRequest)
    end

    # Even a real historical merge says nothing about the current issue.
    stub(fn conn ->
      case conn.request_path do
        "/repos/owner/board/pulls/700" -> Req.Test.json(conn, pull(at))
        "/repos/owner/board/pulls/700/reviews" -> Req.Test.json(conn, [])
        "/repos/owner/board/commits/abc/check-runs" -> Req.Test.json(conn, %{check_runs: []})
      end
    end)

    assert :ok = MergedPull.perform(job)
    assert Repo.get!(Task, task.id).state == "queued"
  end

  test "old, unrelated and unidentified tickets do not enqueue on startup", %{repo: repo, at: at} do
    stub(fn _ -> flunk("No GitHub read expected") end)
    t = AgentState.normalize(ticket(at))

    MergedPull.enqueue_recent(repo, [
      Map.put(t, "repository", nil),
      Map.put(t, "repository", "owner/other"),
      Map.put(t, "ended_at", DateTime.add(DateTime.utc_now(), -301))
    ])

    refute_enqueued(worker: MergedPull)
  end

  test "a rate limit backs off; obsolete work does not make another request", %{repo: repo} do
    job = %Oban.Job{args: %{"number" => 700, "repo_id" => repo.id}}

    stub(fn conn ->
      conn |> Plug.Conn.put_resp_header("retry-after", "120") |> Plug.Conn.send_resp(429, "wait")
    end)

    assert {:snooze, 120} = MergedPull.perform(job)
    assert :ok = MergedPull.perform(%{job | inserted_at: DateTime.add(DateTime.utc_now(), -310)})
    refute Repo.exists?(PullRequest)
  end
end
