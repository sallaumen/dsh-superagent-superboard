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

  test "the sync event counts only this run's errors, not old ones", %{repo: repo} do
    Board.log_event(repo.id, "pull_error", "#1", %{"reason" => "old"})
    Board.log_event(repo.id, "comment_error", "#2", %{"reason" => "old"})
    Board.log_event(repo.id, "commit_error", "#3", %{"reason" => "old"})

    stub_github(fn conn -> Req.Test.json(conn, []) end)

    assert Sync.sync_repo(client(), repo) == :ok

    sync = Board.latest_sync(repo)
    assert sync.payload["errors"] == 0
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

  test "an approved review reaches the stored pull", %{repo: repo} do
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
          Req.Test.json(conn, [%{"id" => 1, "state" => "APPROVED", "user" => %{"login" => "rev"}}])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    stored = Repo.one(from p in AgentBoard.Board.PullRequest, where: p.number == 9)
    assert stored.review_state == "approved"
    assert stored.head_sha == "abc"
  end

  test "a long issue body reaches the board whole", %{repo: repo} do
    long = String.duplicate("descrição ", 900)

    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" ->
          Req.Test.json(conn, [Map.put(issue(7, "open"), "body", long)])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok
    assert Repo.one(Task).body == long
  end

  test "an issue's edited body reaches the board on the next sync", %{repo: repo} do
    for body <- ["first words", "edited words"] do
      stub_github(fn conn ->
        case conn.request_path do
          "/repos/sallaumen/arena-rogue/issues" ->
            Req.Test.json(conn, [Map.put(issue(7, "open"), "body", body)])

          _ ->
            Req.Test.json(conn, [])
        end
      end)

      assert Sync.sync_repo(client(), repo) == :ok
    end

    assert Repo.one(Task).body == "edited words"
  end

  test "a sync does not make an unchanged task look updated now", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" -> Req.Test.json(conn, [issue(7, "open")])
        _ -> Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok
    long_ago = ~U[2026-01-01 00:00:00Z]
    Repo.update_all(Task, set: [updated_at: long_ago])

    assert Sync.sync_repo(client(), repo) == :ok
    assert Repo.one(Task).updated_at == long_ago
  end

  test "the sync stores the PR's branch and the issues its body closes", %{repo: repo} do
    pull = fn number, head, body ->
      %{
        "number" => number,
        "title" => "PR #{number}",
        "state" => "open",
        "html_url" => "https://github.com/sallaumen/arena-rogue/pull/#{number}",
        "user" => %{"login" => "sallaumen-agent"},
        "created_at" => "2026-11-04T00:00:00Z",
        "body" => body,
        "head" => Map.put(head, "sha", "abc")
      }
    end

    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" ->
          Req.Test.json(conn, [issue(7, "open")])

        "/repos/sallaumen/arena-rogue/pulls" ->
          Req.Test.json(conn, [
            pull.(
              21,
              %{"ref" => "agent/7-fix", "repo" => %{"full_name" => "sallaumen/arena-rogue"}},
              "Closes #7\n\nAlso see #3."
            ),
            pull.(22, %{"ref" => "main", "repo" => %{"full_name" => "someone/arena-rogue"}}, nil),
            pull.(23, %{"ref" => "gone", "repo" => nil}, "Fixes #7")
          ])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    stored = fn number ->
      Repo.one(from p in AgentBoard.Board.PullRequest, where: p.number == ^number)
    end

    assert %{head_ref: "agent/7-fix", closes_issues: [7]} = stored.(21)
    # A fork's branch, or a deleted fork's, is not a branch of this repository.
    assert %{head_ref: nil, closes_issues: []} = stored.(22)
    assert %{head_ref: nil, closes_issues: [7]} = stored.(23)

    task = Repo.one(from t in Task, where: t.number == 7)
    session = %{git_branch: "agent/7-fix", origin_url: "https://github.com/sallaumen/arena-rogue"}

    assert AgentBoard.Attribution.for_session(session, Board.attribution_index()) ==
             {:task, task.id, :branch}
  end

  test "all/1 syncs every active repo with the injected client", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" -> Req.Test.json(conn, [issue(7, "open")])
        _ -> Req.Test.json(conn, [])
      end
    end)

    assert Sync.all(client()) == 1
    assert Repo.one(from t in Task, where: t.number == 7) != nil
    assert repo.name == "arena-rogue"
  end

  describe "the GitHub quota" do
    # 287 pulls with two reads each, every five minutes, spent more than the
    # account's 5000 an hour and froze the board for the rest of the hour.
    defp recent_pull(number, sha, merged_at) do
      %{
        "number" => number,
        "title" => "PR #{number}",
        "state" => if(merged_at, do: "closed", else: "open"),
        "merged_at" => merged_at,
        "html_url" => "https://github.com/x/y/pull/#{number}",
        "user" => %{"login" => "sallaumen"},
        "created_at" => "2026-11-04T00:00:00Z",
        "body" => nil,
        "head" => %{
          "ref" => "b",
          "sha" => sha,
          "repo" => %{"full_name" => "sallaumen/arena-rogue"}
        }
      }
    end

    defp stub_pulls(pulls, runs) do
      test = self()

      stub_github(fn conn ->
        cond do
          conn.request_path == "/repos/sallaumen/arena-rogue/pulls" ->
            Req.Test.json(conn, pulls)

          String.ends_with?(conn.request_path, "/reviews") ->
            send(test, {:read, :reviews, conn.request_path})
            Req.Test.json(conn, [%{"state" => "APPROVED", "user" => %{"login" => "a"}}])

          String.ends_with?(conn.request_path, "/check-runs") ->
            send(test, {:read, :checks, conn.request_path})
            Req.Test.json(conn, %{"check_runs" => runs})

          true ->
            Req.Test.json(conn, [])
        end
      end)
    end

    defp merged_at, do: DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.to_iso8601()

    defp stored(number) do
      Repo.one(from p in AgentBoard.Board.PullRequest, where: p.number == ^number)
    end

    defp flush_reads do
      receive do
        {:read, _kind, _path} -> flush_reads()
      after
        0 -> :ok
      end
    end

    @done [%{"name" => "ci", "status" => "completed", "conclusion" => "success"}]
    @running [%{"name" => "ci", "status" => "in_progress", "conclusion" => nil}]

    test "a pull already stored as merged is not read again and keeps its rollups", %{repo: repo} do
      stub_pulls([recent_pull(9, "abc", merged_at())], @done)

      assert Sync.sync_repo(client(), repo) == :ok
      assert_received {:read, :reviews, _path}
      assert_received {:read, :checks, _path}
      first = stored(9)
      assert first.review_state
      assert first.checks_state
      flush_reads()

      assert Sync.sync_repo(client(), repo) == :ok
      refute_received {:read, _kind, _path}
      second = stored(9)
      assert second.review_state == first.review_state
      assert second.checks_state == first.checks_state
    end

    test "a pull that just merged is read once more", %{repo: repo} do
      stub_pulls([recent_pull(9, "abc", nil)], @done)
      assert Sync.sync_repo(client(), repo) == :ok
      flush_reads()

      stub_pulls([recent_pull(9, "abc", merged_at())], @done)
      assert Sync.sync_repo(client(), repo) == :ok

      assert_received {:read, :reviews, _path}
      assert stored(9).state == "merged"
    end

    test "an open pull is read on every sync", %{repo: repo} do
      stub_pulls([recent_pull(9, "abc", nil)], @done)
      assert Sync.sync_repo(client(), repo) == :ok
      flush_reads()

      assert Sync.sync_repo(client(), repo) == :ok
      assert_received {:read, :checks, _path}
    end

    test "a merged pull whose checks were still running is read until they end", %{repo: repo} do
      stub_pulls([recent_pull(9, "abc", merged_at())], @running)
      assert Sync.sync_repo(client(), repo) == :ok
      assert stored(9).checks_state == "pending"
      flush_reads()

      stub_pulls([recent_pull(9, "abc", merged_at())], @done)
      assert Sync.sync_repo(client(), repo) == :ok
      assert_received {:read, :checks, _path}
      refute stored(9).checks_state == "pending"
    end

    test "a merged pull whose read failed is read again", %{repo: repo} do
      pulls = [recent_pull(9, "abc", merged_at())]

      stub_github(fn conn ->
        cond do
          conn.request_path == "/repos/sallaumen/arena-rogue/pulls" ->
            Req.Test.json(conn, pulls)

          String.ends_with?(conn.request_path, "/check-runs") ->
            Plug.Conn.send_resp(conn, 500, "{}")

          true ->
            Req.Test.json(conn, [])
        end
      end)

      assert Sync.sync_repo(client(), repo) == :ok
      assert stored(9).checks_state == nil

      stub_pulls(pulls, @done)
      assert Sync.sync_repo(client(), repo) == :ok
      assert_received {:read, :checks, _path}
      assert stored(9).checks_state == "success"
    end

    test "a merged pull with no checks at all is not read again", %{repo: repo} do
      stub_pulls([recent_pull(9, "abc", merged_at())], [])
      assert Sync.sync_repo(client(), repo) == :ok
      assert stored(9).checks_state == "none"
      flush_reads()

      assert Sync.sync_repo(client(), repo) == :ok
      refute_received {:read, _kind, _path}
    end

    defp stub_failing_read(pulls, failing, runs) do
      stub_github(fn conn ->
        cond do
          conn.request_path == "/repos/sallaumen/arena-rogue/pulls" ->
            Req.Test.json(conn, pulls)

          String.ends_with?(conn.request_path, failing) ->
            Plug.Conn.send_resp(conn, 500, "{}")

          String.ends_with?(conn.request_path, "/check-runs") ->
            Req.Test.json(conn, %{"check_runs" => runs})

          true ->
            Req.Test.json(conn, [])
        end
      end)
    end

    test "an open pull keeps good checks when only its reviews could not be read",
         %{repo: repo} do
      stub_failing_read([recent_pull(9, "abc", nil)], "/reviews", @done)
      assert Sync.sync_repo(client(), repo) == :ok
      assert stored(9).checks_state == "success"
    end

    test "an open pull keeps what it knew when its checks could not be read", %{repo: repo} do
      stub_pulls([recent_pull(9, "abc", nil)], @done)
      assert Sync.sync_repo(client(), repo) == :ok
      first = stored(9)
      assert first.checks_state == "success"

      stub_failing_read([recent_pull(9, "abc", nil)], "/check-runs", @done)
      assert Sync.sync_repo(client(), repo) == :ok
      second = stored(9)
      assert second.checks_state == "success"
      assert second.checks_changed_at == first.checks_changed_at
    end

    test "an open pull does not lend the old commit's checks to a new one", %{repo: repo} do
      stub_pulls([recent_pull(9, "abc", nil)], @done)
      assert Sync.sync_repo(client(), repo) == :ok
      assert stored(9).checks_state == "success"

      stub_failing_read([recent_pull(9, "def", nil)], "/check-runs", @done)
      assert Sync.sync_repo(client(), repo) == :ok
      assert stored(9).checks_state == nil
    end

    test "a merged pull whose reviews could not be read is read again", %{repo: repo} do
      pulls = [recent_pull(9, "abc", merged_at())]
      stub_failing_read(pulls, "/reviews", @done)
      assert Sync.sync_repo(client(), repo) == :ok
      assert stored(9).checks_state == nil

      stub_pulls(pulls, @done)
      assert Sync.sync_repo(client(), repo) == :ok
      assert_received {:read, :reviews, _path}
      assert stored(9).checks_state == "success"
    end

    test "a pull closed long ago without merging is not read", %{repo: repo} do
      closed_at = DateTime.utc_now() |> DateTime.add(-40, :day) |> DateTime.to_iso8601()

      pull =
        recent_pull(9, "abc", nil) |> Map.merge(%{"state" => "closed", "closed_at" => closed_at})

      stub_pulls([pull], @done)

      assert Sync.sync_repo(client(), repo) == :ok
      refute_received {:read, _kind, _path}
    end

    # The header, Activity and the voice read this count: a check or review
    # read that failed is an error of this sync, like an issue or pull read.
    test "a failed check or review read counts in the sync's errors", %{repo: repo} do
      stub_github(fn conn ->
        cond do
          conn.request_path == "/repos/sallaumen/arena-rogue/pulls" ->
            Req.Test.json(conn, [recent_pull(31, "abc", nil)])

          String.ends_with?(conn.request_path, "/reviews") ->
            Plug.Conn.send_resp(conn, 500, "boom")

          String.ends_with?(conn.request_path, "/check-runs") ->
            Plug.Conn.send_resp(conn, 500, "boom")

          true ->
            Req.Test.json(conn, [])
        end
      end)

      assert Sync.sync_repo(client(), repo) == :ok

      sync = Enum.find(Board.events(repo), &(&1.kind == "sync"))
      assert sync.payload["errors"] == 2
    end
  end

  test "an old merged pull skips its reviews", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/pulls" ->
          Req.Test.json(conn, [
            %{
              "number" => 9,
              "title" => "Old",
              "state" => "closed",
              "merged_at" => "2025-01-01T00:00:00Z",
              "html_url" => "https://github.com/x/y/pull/9",
              "user" => %{"login" => "s"},
              "created_at" => "2025-01-01T00:00:00Z",
              "head" => %{"sha" => "abc"}
            }
          ])

        "/repos/sallaumen/arena-rogue/pulls/9/reviews" ->
          send(self(), :reviews_requested)
          Req.Test.json(conn, [])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok
    refute_received :reviews_requested
  end

  test "ticket numbers come from channels as integers", _ctx do
    ticket = %{
      "mandate" => %{"basis" => %{"scope" => %{}}},
      "channels" => [
        %{"address" => %{"number" => "42"}},
        %{"address" => %{"number" => 43}}
      ]
    }

    assert AgentBoard.AgentState.ticket_numbers(ticket) == [42, 43]
  end

  test "a repository without issues still syncs its pulls", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" ->
          Plug.Conn.send_resp(conn, 404, ~s({"message": "Not Found"}))

        "/repos/sallaumen/arena-rogue/pulls" ->
          Req.Test.json(conn, [
            %{
              "number" => 9,
              "title" => "Only PRs",
              "state" => "open",
              "html_url" => "https://github.com/x/y/pull/9",
              "user" => %{"login" => "sallaumen"},
              "created_at" => "2026-11-04T00:00:00Z",
              "head" => %{"sha" => "abc"}
            }
          ])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok
    assert Repo.one(from p in AgentBoard.Board.PullRequest, where: p.number == 9) != nil
    assert Enum.any?(Board.events(repo), &(&1.kind == "issues_unavailable"))
  end

  test "a repository whose Issues are gone (410) still syncs", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" -> Plug.Conn.send_resp(conn, 410, "{}")
        _ -> Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok
    assert Enum.any?(Board.events(repo), &(&1.kind == "issues_unavailable"))
  end

  # A refused token, a 5xx after the retries or a timeout read no issue
  # state: a fresh `sync` event would tell the board everything is current.
  test "an issues read that fails is a sync error, not a fresh sync", %{repo: repo} do
    failures = [
      &Plug.Conn.send_resp(&1, 401, ~s({"message": "Bad credentials"})),
      &Plug.Conn.send_resp(&1, 502, "bad gateway"),
      &Req.Test.transport_error(&1, :timeout)
    ]

    for failure <- failures do
      stub_github(fn conn ->
        case conn.request_path do
          "/repos/sallaumen/arena-rogue/issues" -> failure.(conn)
          _ -> Req.Test.json(conn, [])
        end
      end)

      assert {:error, _exception} = Sync.sync_repo(client(), repo)
    end

    kinds = Enum.map(Board.events(repo), & &1.kind)
    assert Enum.count(kinds, &(&1 == "sync_error")) == 3
    refute "sync" in kinds
    refute "issues_unavailable" in kinds
  end

  test "a merged pull still gets its rollups", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/pulls" ->
          Req.Test.json(conn, [
            %{
              "number" => 9,
              "title" => "Merged PR",
              "state" => "closed",
              "merged_at" => "2026-11-04T00:00:00Z",
              "html_url" => "https://github.com/x/y/pull/9",
              "user" => %{"login" => "sallaumen"},
              "created_at" => "2026-11-04T00:00:00Z",
              "head" => %{"sha" => "abc"}
            }
          ])

        "/repos/sallaumen/arena-rogue/pulls/9/reviews" ->
          Req.Test.json(conn, [%{"id" => 1, "state" => "APPROVED", "user" => %{"login" => "rev"}}])

        "/repos/sallaumen/arena-rogue/commits/abc/check-runs" ->
          Req.Test.json(conn, %{
            "check_runs" => [
              %{"conclusion" => "success", "name" => "ci", "status" => "completed"}
            ]
          })

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    stored = Repo.one(from p in AgentBoard.Board.PullRequest, where: p.number == 9)
    assert stored.review_state == "approved"
    assert stored.checks_state == "success"
  end

  test "changes_requested wins over approved through the sync", %{repo: repo} do
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
          Req.Test.json(conn, [
            %{"id" => 1, "state" => "APPROVED", "user" => %{"login" => "a"}},
            %{"id" => 2, "state" => "CHANGES_REQUESTED", "user" => %{"login" => "b"}}
          ])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    stored = Repo.one(from p in AgentBoard.Board.PullRequest, where: p.number == 9)
    assert stored.review_state == "changes_requested"
  end

  test "a broken review fetch still stores the PR", %{repo: repo} do
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

    stored = Repo.one(from p in AgentBoard.Board.PullRequest, where: p.number == 9)
    assert stored != nil
    assert Enum.any?(Board.events(repo), &(&1.kind == "review_error"))
  end

  test "an invalid pull logs a pull_error", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/pulls" ->
          Req.Test.json(conn, [
            %{
              "number" => 9,
              "title" => nil,
              "state" => "open",
              "html_url" => "https://github.com/x/y/pull/9",
              "user" => %{"login" => "sallaumen"},
              "created_at" => "2026-11-04T00:00:00Z",
              "head" => %{"sha" => "abc"}
            }
          ])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok
    assert Enum.any?(Board.events(repo), &(&1.kind == "pull_error"))
    assert Repo.one(from p in AgentBoard.Board.PullRequest, where: p.number == 9) == nil
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
    assert Enum.any?(Board.events(repo), &(&1.kind == "review_error"))
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

  test "a comment without id does not duplicate across two syncs", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" ->
          Req.Test.json(conn, [issue(7, "open")])

        "/repos/sallaumen/arena-rogue/issues/7/comments" ->
          Req.Test.json(conn, [
            %{"id" => nil, "user" => %{"login" => "sallaumen"}, "body" => "same"}
          ])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok
    assert Sync.sync_repo(client(), repo) == :ok

    task = Repo.one(from t in Task, where: t.number == 7)
    assert length(Board.comments(task)) == 1
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

  test "the sync pulls the comments of a task waiting on the person", %{repo: repo} do
    for {number, state} <- [{8, "question"}, {9, "blocked"}] do
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: number,
        title: "Issue #{number}",
        state: state
      })
      |> Repo.insert!()
    end

    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" ->
          Req.Test.json(conn, [issue(8, "open"), issue(9, "open")])

        "/repos/sallaumen/arena-rogue/issues/" <> rest ->
          [number, "comments"] = String.split(rest, "/")

          Req.Test.json(conn, [
            %{
              "id" => String.to_integer(number) * 10,
              "user" => %{"login" => "sallaumen-agent"},
              "body" => "Feito: o PR #28 está pronto para revisão."
            }
          ])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    for number <- [8, 9] do
      task = Repo.one(from t in Task, where: t.number == ^number)
      assert [%{kind: "agent"}] = Board.comments(task)
    end
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

  test "an issue closed after it entered the board leaves the queue", %{repo: repo} do
    for state <- ["open", "closed"] do
      stub_github(fn conn ->
        case conn.request_path do
          "/repos/sallaumen/arena-rogue/issues" -> Req.Test.json(conn, [issue(22, state)])
          _ -> Req.Test.json(conn, [])
        end
      end)

      assert Sync.sync_repo(client(), repo) == :ok
    end

    assert %Task{state: "done"} = Repo.one(from t in Task, where: t.number == 22)
  end

  test "a stopped task keeps its state when its issue closes", %{repo: repo} do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" -> Req.Test.json(conn, [issue(23, "open")])
        _ -> Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok

    Repo.update_all(from(t in Task, where: t.number == 23),
      set: [stopped: true, state: "stopped"]
    )

    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" -> Req.Test.json(conn, [issue(23, "closed")])
        _ -> Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok
    assert %Task{state: "stopped"} = Repo.one(from t in Task, where: t.number == 23)
  end

  # GitHub's updated_at for these issues: after the stored decisions the
  # tests set to `@long_ago`, before any decision a sync makes now.
  @long_ago ~U[2026-01-01 00:00:00Z]

  defp sync_issue_states(repo, number, states) do
    Enum.each(
      states,
      &sync_issue(repo, Map.put(issue(number, &1), "updated_at", "2026-11-04T00:00:00Z"))
    )
  end

  defp sync_issue(repo, issue) do
    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" -> Req.Test.json(conn, [issue])
        _ -> Req.Test.json(conn, [])
      end
    end)

    assert Sync.sync_repo(client(), repo) == :ok
  end

  test "a reopened issue goes back to the queue", %{repo: repo} do
    sync_issue_states(repo, 24, ["closed"])
    Repo.update_all(Task, set: [state_changed_at: @long_ago])

    sync_issue_states(repo, 24, ["open"])

    task = Repo.one(from t in Task, where: t.number == 24)
    assert task.state == "queued"
    assert DateTime.compare(task.state_changed_at, @long_ago) == :gt
  end

  test "a reopened issue of a stopped or archived task keeps its state", %{repo: repo} do
    sync_issue_states(repo, 25, ["closed"])
    Repo.update_all(Task, set: [archived: true])

    sync_issue_states(repo, 25, ["open"])

    assert %Task{state: "done", archived: true} = Repo.one(Task)
  end

  test "a merged ticket remains done without a newer reopen, but a confirmed reopen survives sync and poll",
       %{repo: repo} do
    path = Path.join(System.tmp_dir!(), "sync-reopen-#{System.unique_integer([:positive])}.db")
    {:ok, db} = Exqlite.Sqlite3.open(path)
    previous = Application.get_env(:agent_board, :state_db)

    on_exit(fn ->
      Exqlite.Sqlite3.close(db)
      File.rm(path)
      Application.put_env(:agent_board, :state_db, previous)
    end)

    merged =
      ~s({"channels":[{"address":{"url":"https://github.com/sallaumen/arena-rogue/issues/26"}}],"mandate":{"basis":{"scope":{"number":26}}},"assignments":[{"state":"ended"}],"ended":{"at":"2026-11-07T00:01:15.000Z","by":"executor","outcome":"merged"}})

    :ok = Exqlite.Sqlite3.execute(db, "create table ticket (value text)")
    :ok = Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('#{merged}')")
    Application.put_env(:agent_board, :state_db, path)

    sync_issue_states(repo, 26, ["closed"])
    Repo.update_all(Task, set: [state_changed_at: @long_ago])

    # The reopen puts it back in the queue and the merged ticket makes it done.
    sync_issue_states(repo, 26, ["open"])
    decided = Repo.one(Task)
    assert decided.state == "done"
    assert DateTime.compare(decided.state_changed_at, @long_ago) == :gt

    # The same issue again is no new reopen: the decision, stamped after the
    # issue's updated_at, stands.
    decided_at = ~U[2026-11-05 00:00:00Z]
    Repo.update_all(Task, set: [state_changed_at: decided_at])
    sync_issue_states(repo, 26, ["open"])
    assert %Task{state: "done", state_changed_at: ^decided_at} = Repo.one(Task)

    reopened = ~U[2026-11-07 01:00:00Z]
    updated = Map.put(issue(26, "open"), "updated_at", DateTime.to_iso8601(reopened))

    stub_github(fn conn ->
      case conn.request_path do
        "/graphql" ->
          send(self(), :read_history)

          Req.Test.json(conn, %{
            data: %{
              repository: %{
                i26: %{
                  number: 26,
                  state: "OPEN",
                  timelineItems: %{nodes: [%{__typename: "ReopenedEvent", createdAt: reopened}]}
                }
              }
            }
          })

        "/repos/sallaumen/arena-rogue/issues" ->
          Req.Test.json(conn, [updated])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    # The pre-fix board may already have decided "done" after the reopen.
    Repo.update_all(Task, set: [state_changed_at: DateTime.add(reopened, 120)])
    assert :ok = Sync.sync_repo(client(), repo)
    assert_received :read_history

    assert %Task{state: "queued", github_reopened_at: ^reopened, state_changed_at: at} =
             Repo.one(Task)

    AgentBoard.TicketPoller.poll(%{})
    assert :ok = Sync.sync_repo(client(), repo)
    refute_received :read_history
    assert %Task{state: "queued", state_changed_at: ^at} = Repo.one(Task)

    # New work is not suppressed by the boundary.
    AgentBoard.TicketOverlay.apply(repo, 26, "running", DateTime.add(reopened, 10))
    assert Repo.one(Task).state == "running"
    sync_issue_states(repo, 26, ["closed"])
    assert Repo.one(Task).state == "done"
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

  test "a title of GitHub's full 256 characters does not fail the sync", %{repo: repo} do
    title = String.duplicate("a", 256)

    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/issues" ->
          Req.Test.json(conn, [issue(11, "open") |> Map.put("title", title)])

        _ ->
          Req.Test.json(conn, [])
      end
    end)

    Sync.sync_repo(client(), repo)

    assert Repo.one(from t in Task, where: t.number == 11, select: t.title) ==
             String.duplicate("a", 255)
  end

  test "a rate limit on one pull stops the run instead of asking for every other", %{repo: repo} do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    pull = fn number ->
      %{
        "number" => number,
        "title" => "PR #{number}",
        "state" => "open",
        "html_url" => "https://github.com/sallaumen/arena-rogue/pull/#{number}",
        "user" => %{"login" => "s"},
        "head" => %{"sha" => "abc#{number}", "ref" => "b#{number}"},
        "created_at" => "2026-11-04T00:00:00Z",
        "updated_at" => "2026-11-04T00:00:00Z"
      }
    end

    stub_github(fn conn ->
      case conn.request_path do
        "/repos/sallaumen/arena-rogue/pulls" ->
          Req.Test.json(conn, [pull.(1), pull.(2), pull.(3)])

        "/repos/sallaumen/arena-rogue/issues" ->
          Req.Test.json(conn, [])

        _other ->
          Agent.update(calls, &(&1 + 1))
          Plug.Conn.send_resp(conn, 429, "slow down")
      end
    end)

    assert {:error, %AgentBoard.GitHub.RateLimited{}} = Sync.sync_repo(client(), repo)
    assert Agent.get(calls, & &1) == 1

    kinds = Enum.map(Board.events(repo), & &1.kind)
    assert "sync_error" in kinds
    refute "review_error" in kinds
    refute "check_error" in kinds

    assert %{payload: %{"rate_limited" => true, "retry_after" => 60}} =
             Enum.find(Board.events(repo), &(&1.kind == "sync_error"))
  end
end
