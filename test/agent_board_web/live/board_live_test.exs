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

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{PullRequest, Task}

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
    assert html =~ "f0b3b3"
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

    view |> element("button", "Close") |> render_click()
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
