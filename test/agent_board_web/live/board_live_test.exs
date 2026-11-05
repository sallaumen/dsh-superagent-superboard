defmodule AgentBoardWeb.BoardLiveTest do
  @moduledoc "The board's UI: the columns render and the tasks can be created."
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox

  # The LiveView runs in its own process: allow it to use the test's
  # transaction, which is the supported way to keep async: true.
  defp allow_view(view) do
    Sandbox.allow(AgentBoard.Repo, self(), view.pid)
    view
  end

  alias AgentBoard.AI.Call
  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{PullRequest, Task}

  test "issues_unavailable is amber, not red", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    Board.log_event(repo.id, "issues_unavailable", "sallaumen/arena-rogue", %{"reason" => "404"})

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "text-warning"
    refute html =~ "text-error"
  end

  test "a per-item error event is shown as an error", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    Board.log_event(repo.id, "issue_error", "#7", %{"reason" => "boom"})

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "text-error"
  end

  test "the sync line says 1 error, not 1 errors", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    Board.log_event(repo.id, "sync", "sallaumen/arena-rogue", %{"errors" => 1, "issues" => 0})

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "1 error"
    refute html =~ "1 errors"
  end

  test "a long error payload is truncated in the activity", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    Board.log_event(repo.id, "sync_error", "x", %{"reason" => String.duplicate("boom ", 80)})

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "…"
    refute html =~ String.duplicate("boom ", 80)
  end

  test "the health line finds sync beyond the 20 recent events", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "health")
    Board.log_event(repo.id, "sync", "fixture/health", %{"errors" => 0})
    for n <- 1..21, do: Board.log_event(repo.id, "comment_error", "##{n}", %{})

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/health")
    assert has_element?(view, "#sync-status", "clean")
    assert has_element?(view, "#sync-status", "UTC")
  end

  test "sync age describes the last outcome without pretending a failure refreshed data", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "freshness")
    Board.log_event(repo.id, "sync", "fixture/freshness", %{"errors" => 0})
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/freshness")
    assert has_element?(view, "#sync-age[data-sync=true][datetime]", "Last completed sync")

    Board.log_event(repo.id, "sync_error", "fixture/freshness", %{"reason" => "offline"})
    send(view.pid, :board_updated)
    assert has_element?(view, "#sync-age[data-sync=false]", "Last sync attempt")
    assert has_element?(view, "#data-freshness", "Saved data age: unknown")
    assert has_element?(view, "#activity-age[datetime]")
  end

  test "a failed sync supersedes the last clean outcome", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "health")
    Board.log_event(repo.id, "sync", "fixture/health", %{"errors" => 0})
    Board.log_event(repo.id, "sync_error", "fixture/health", %{"reason" => "offline"})

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/health")
    assert has_element?(view, "#sync-status", "sync failed")
    assert has_element?(view, "#sync-status", "showing saved data")
    refute has_element?(view, "#sync-status", "clean")
  end

  test "Dictate task pushes the dictate event", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    view |> element("button", "Dictate task") |> render_click()

    assert_push_event(view, "dictate", %{})
  end

  test "Speak status pushes the board summary", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    view |> element("button", "Speak status") |> render_click()

    assert_push_event(view, "speak", %{text: text})
    assert is_binary(text)
    assert text != ""
  end

  test "a failed ask shows an error, not Question sent", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 801,
      title: "Ask fail",
      state: "queued"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    view |> element("button", "Open") |> render_click()

    view
    |> element("#ask-agent")
    |> render_submit(%{"body" => "hi"})

    assert render(view) =~ "did not reach GitHub"
  end

  test "the conversation label shrinks on small screens", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 303,
      title: "Conv mobile",
      state: "queued"
    })
    |> Repo.insert!()

    task = Repo.get_by(Task, number: 303)

    Board.upsert_comment(
      task,
      %{"id" => 1, "user" => %{"login" => "sallaumen"}, "body" => "hi"},
      "sallaumen-agent"
    )

    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("button", "Open") |> render_click()

    assert render(view) =~ "sm:w-14"
  end

  test "merged history previews five newest pulls and preserves the remaining loaded pulls", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "history")
    now = DateTime.utc_now()

    for number <- 1..7 do
      %PullRequest{}
      |> PullRequest.changeset(%{
        repository_id: repo.id,
        number: number,
        title: "Merged pull #{number}",
        state: "merged",
        merged_at: DateTime.add(now, number, :second)
      })
      |> Repo.insert!()
    end

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/history")

    assert has_element?(view, "#merged-column", "latest 7 loaded")
    assert has_element?(view, "#merged-preview article:nth-child(5)", "Merged pull 3")
    refute has_element?(view, "#merged-preview article:nth-child(6)")
    assert has_element?(view, "#merged-history summary", "Show 2 more merged pull requests")
    assert has_element?(view, "#merged-history article", "Merged pull 2")
    assert has_element?(view, "#merged-history article", "Merged pull 1")
    refute has_element?(view, "#merged-history[open]")
    refute has_element?(view, "#merged-column button[phx-click=act]")
  end

  test "empty merged history has no expansion control", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "empty-history")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/empty-history")

    assert has_element?(view, "#merged-column", "No pull request merged yet.")
    refute has_element?(view, "#merged-history")
  end

  test "missing AI measurements remain unknown", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "measurements")

    %Call{}
    |> Call.changeset(%{
      name: "refine_request",
      engine: "deepseek",
      status: "error",
      duration_ms: nil,
      input_tokens: nil,
      output_tokens: nil
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/measurements")

    assert has_element?(view, ".ai-call-metrics div:first-child", "Latencyunknown")
    assert has_element?(view, ".ai-call-metrics div:nth-child(2)", "Usageunknown")
    assert has_element?(view, ".ai-call-metrics div:last-child", "Est. costunknown")
    refute has_element?(view, ".ai-call-metrics", "0ms")
    refute has_element?(view, ".ai-call-metrics", "0 tokens")
  end

  test "a merged pull shows its review badge", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 404,
      title: "Badge PR",
      state: "merged",
      merged_at: DateTime.utc_now(),
      review_state: "changes_requested"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Badge PR"
    assert html =~ "changes requested"
  end

  test "a merged pull shows its CI badge", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 405,
      title: "CI PR",
      state: "merged",
      merged_at: DateTime.utc_now(),
      checks_state: "failure"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "CI PR"
    assert html =~ "ci failed"
  end

  test "a failed CI names the check", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 406,
      title: "Named CI",
      state: "merged",
      merged_at: DateTime.utc_now(),
      checks_state: "failure",
      checks_failed: "compile"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "ci failed: compile"
  end

  test "a pull with no reviews says so instead of hiding the badge", %{conn: conn} do
    # arena-rogue has few merged pulls, so one more still fits the 30 window.
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 407,
      title: "No review PR",
      state: "merged",
      merged_at: DateTime.utc_now(),
      review_state: "none",
      checks_state: "none"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/")

    # the board opens on o_colmex; switch to arena-rogue
    view |> element("#repo-select") |> render_change(%{"repo" => "sallaumen/arena-rogue"})

    assert render(view) =~ "no review"
    assert render(view) =~ "no ci"
  end

  test "the board sends a content security policy", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert Enum.any?(conn.resp_headers, fn {k, v} ->
             k == "content-security-policy" and v =~ "default-src"
           end)
  end

  test "the version panel shows the running sha and a check button", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "Version"
    assert html =~ "running"
    assert has_element?(view, "#version-panel button", "Check")
  end

  test "the AI panel shows the last calls", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    %Call{}
    |> Call.changeset(%{
      name: "refine_request",
      engine: "deepseek",
      model: "deepseek-flash",
      tier: "fast",
      status: "ok",
      input_tokens: 10,
      output_tokens: 20,
      duration_ms: 123,
      cost_micros: 1_120
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "refine_request"
    assert html =~ "deepseek"
    assert html =~ "123ms"
    assert html =~ "30 tokens"
    assert html =~ "Est. cost"
    assert html =~ "$0.00112"
  end

  test "the board shows the blocked column", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "Blocked"
    assert html =~ "Nothing is blocked."
  end

  test "the repo query param selects a repository", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "o_colmex")
    {:ok, arena} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: arena.id,
      kind: "issue",
      number: 601,
      title: "Arena only",
      state: "queued"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert html =~ "Arena only"
  end

  test "a board_updated message reloads the board", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    assert html =~ "No task is running."

    # a task appears behind the view's back
    repo = Board.repository_by_slug("sallaumen/arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 701,
      title: "Arrived by broadcast",
      state: "running"
    })
    |> Repo.insert!()

    send(view.pid, :board_updated)

    assert render(view) =~ "Arrived by broadcast"
  end

  test "broadcasts keep a single stable card and the open conversation", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "stable")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 9,
        title: "Stable task",
        state: "queued"
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/stable")
    view |> element("#task-#{task.id} button", "Open") |> render_click()

    task |> Task.changeset(%{state: "running"}) |> Repo.update!()
    for _ <- 1..3, do: send(view.pid, :board_updated)

    html = render(view)
    assert length(Regex.scan(~r/id="task-#{task.id}"/, html)) == 1
    assert has_element?(view, "#column-running #task-#{task.id}")
    assert has_element?(view, "#conversation-title", "Stable task")
    assert has_element?(view, "#ask-agent input[name=body]")
  end

  test "switching repos stops listening to the old one", %{conn: conn} do
    {:ok, colmex} = Board.add_repository("sallaumen", "o_colmex")
    {:ok, _arena} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/o_colmex")

    view
    |> element("#repo-select")
    |> render_change(%{"repo" => "sallaumen/arena-rogue"})

    Board.broadcast(colmex.id)
    refute_receive :board_updated, 100
  end

  test "selecting a repository updates the url", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "o_colmex")
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("#repo-select")
    |> render_change(%{"repo" => "sallaumen/arena-rogue"})

    assert_patch(view, "/?repo=sallaumen%2Farena-rogue")
  end

  test "an unknown repository slug renders the empty board", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/?repo=nobody/nothing")

    assert html =~ "No task is running."
  end

  test "the sync line is announced politely", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(role="status")
    assert html =~ ~s(aria-live="polite")
  end

  test "external links open with noopener", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 501,
      title: "Linked task",
      state: "queued",
      url: "https://github.com/sallaumen/arena-rogue/issues/501"
    })
    |> Repo.insert!()

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(rel="noopener noreferrer")
  end

  test "the controls carry accessible names", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(aria-label="Repository")
    assert html =~ ~s(aria-label="Owner")
    assert html =~ ~s(aria-label="Repository name")
  end

  test "the header carries the brand and the tagline", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Agent board"
    assert html =~ "the agent&#39;s work, live"
  end

  test "the board renders the columns", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Running"
    assert html =~ "Merged"
    assert html =~ "Queued"
  end

  test "the track inputs shrink on small screens", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "sm:w-28"
    assert html =~ "sm:w-36"
  end

  test "the columns stack on small screens", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "grid-cols-1"
    assert html =~ "lg:grid-cols-4"
  end

  test "the board renders the tracked repository", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "sallaumen/arena-rogue"
  end

  test "the board renders without a repository", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "No repository tracked yet."
  end

  test "a broadcast reaches the board subscribers", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, _view, _html} = live(conn, ~p"/")

    assert Board.subscribe(repo.id) == :ok
    Board.broadcast(repo.id)

    assert_receive :board_updated
  end

  test "the board opens on o_colmex when it is tracked", %{conn: conn} do
    {:ok, _arena} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, _colmex} = Board.add_repository("sallaumen", "o_colmex")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "o_colmex"
  end

  test "an activity row with errors is highlighted", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    Board.log_event(repo.id, "sync", "sallaumen/arena-rogue", %{"pulls" => 1, "errors" => 2})

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "errors: 2"
    assert html =~ "text-error"
  end

  test "the header shows the last sync and its errors", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    Board.log_event(repo.id, "sync", "sallaumen/arena-rogue", %{"pulls" => 1, "errors" => 2})

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "synced"
    assert html =~ "2 errors"
  end

  test "the activity panel shows the recorded events", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    Board.log_event(repo.id, "sync", "sallaumen/arena-rogue", %{"pulls" => 8})

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Activity"
    assert html =~ "sync"
    assert html =~ "pulls: 8"
  end

  test "repository form recovery does not close the current panel", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "recovery")
    {:ok, view, _html} = live(conn, "/?repo=fixture/recovery&panel=intake")
    view |> element("#repo-select") |> render_change(%{"repo" => "fixture/recovery"})
    refute_patched(view)
    assert has_element?(view, "#board-page[data-panel=intake]")
  end

  test "panels are URL state and malformed conversation links cannot open another repo's task", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "panels")
    {:ok, other} = Board.add_repository("fixture", "other")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: other.id,
        kind: "issue",
        number: 1,
        title: "Other repo",
        state: "queued"
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, "/?repo=fixture/panels&panel=conversation&task=#{task.id}")
    refute has_element?(view, "#conversation")
    assert has_element?(view, "#board-page[data-panel='']")

    render_patch(view, "/?repo=fixture/panels&panel=conversation&task=invalid")
    refute has_element?(view, "#conversation")
    view |> element("#open-ai") |> render_click()
    assert_patch(view, "/?panel=ai&repo=fixture%2Fpanels")
    assert has_element?(view, "#board-page[data-panel=ai]")

    render_patch(view, "/?repo=#{repo.owner}/#{repo.name}")
    assert has_element?(view, "#board-page[data-panel='']")
  end

  test "closing the conversation hides the panel", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 89,
      title: "Close me",
      state: "queued"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("button", "Open") |> render_click()
    assert render(view) =~ "Conversation"

    view |> element("#panel-conversation button", "Close") |> render_click()
    refute render(view) =~ "Conversation"
  end

  test "two clients receive the same broadcast", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    {:ok, first, _html} = live(conn, ~p"/")
    {:ok, second, _html} = live(build_conn(), ~p"/")

    allow_view(first)
    allow_view(second)

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 101,
      title: "Both clients see this",
      state: "queued"
    })
    |> Repo.insert!()

    Board.broadcast(repo.id)

    assert render(first) =~ "Both clients see this"
    assert render(second) =~ "Both clients see this"
  end

  test "the speak event pushes the summary", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("button", "Speak status") |> render_click()

    assert_push_event(view, "speak", %{text: text})
    assert text =~ "calm"
  end

  test "switching repositories closes the previous conversation", %{conn: conn} do
    {:ok, first} = Board.add_repository("fixture", "first")
    {:ok, _} = Board.add_repository("fixture", "second")

    %Task{}
    |> Task.changeset(%{repository_id: first.id, title: "Old context", number: 88})
    |> Repo.insert!()

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/first")
    view |> element("button", "Open") |> render_click()
    assert has_element?(view, "#conversation")

    view |> element("#repo-select") |> render_change(%{"repo" => "fixture/second"})

    refute has_element?(view, "#conversation")
    refute has_element?(view, "#ask-agent")
  end

  test "broadcast refreshes the open conversation", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "conversation")

    task =
      %Task{}
      |> Task.changeset(%{repository_id: repo.id, title: "Fresh comments", number: 89})
      |> Repo.insert!()

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/conversation")
    view |> element("button", "Open") |> render_click()

    Board.upsert_comment(
      task,
      %{"id" => 42, "user" => %{"login" => "agent"}, "body" => "New evidence"},
      "agent"
    )

    send(view.pid, :board_updated)

    assert render(view) =~ "New evidence"
  end

  test "opening a task shows the conversation panel", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 88,
      title: "Open me",
      state: "queued"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("button", "Open") |> render_click()

    assert render(view) =~ "Conversation"
    assert render(view) =~ "No messages yet"
  end

  test "the network buttons disable while the request is in flight", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "phx-disable-with"
    assert html =~ "Creating"
    assert render(view) =~ "Track repo"
  end

  test "the dictate event pushes the dictation request", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("button", "Dictate task") |> render_click()

    assert_push_event(view, "dictate", %{})
  end
end
