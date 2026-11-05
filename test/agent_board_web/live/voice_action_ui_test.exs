defmodule AgentBoardWeb.VoiceActionUITest do
  @moduledoc "Voice task actions require a current, explicit UI confirmation."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  @stub __MODULE__.GitHubStub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn -> Application.delete_env(:agent_board, :github_client) end)
    :ok
  end

  defp task(repo, number) do
    %Task{}
    |> Task.changeset(%{repository_id: repo.id, number: number, title: "Review ##{number}"})
    |> Repo.insert!()
  end

  defp preview(view, command) do
    render_hook(view, "voice_transcript", %{"text" => command})
    view |> form("#voice-command-form", %{"text" => command}) |> render_submit()
  end

  test "review and cancel do not change a task or call GitHub", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "voice-review")
    task = task(repo, 42)
    {:ok, view, _} = live(conn, "/?repo=fixture/voice-review")

    preview(view, "stop task #42")
    assert has_element?(view, ".voice-action-review", "Closes the GitHub issue")
    assert has_element?(view, ".voice-action-review", "fixture/voice-review")
    assert Repo.get!(Task, task.id).state == "queued"

    view |> element("button[phx-click=voice_cancel_action]") |> render_click()
    refute has_element?(view, ".voice-action-review")
    assert Repo.get!(Task, task.id).state == "queued"
    assert Board.events(repo, 5) == []
  end

  test "archive confirmation changes only the reviewed task and is single use", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "voice-archive")
    task = task(repo, 7)
    {:ok, view, _} = live(conn, "/?repo=fixture/voice-archive")

    preview(view, "archive task #7")
    assert Repo.get!(Task, task.id).state == "queued"
    view |> element("button[phx-click=voice_confirm_action]") |> render_click()

    assert Repo.get!(Task, task.id).state == "archived"
    assert has_element?(view, ".voice-command-result[data-kind=success]", "Archived task #7")

    assert [%{kind: "voice_action", payload: %{"action" => "archive", "result" => "completed"}}] =
             Board.events(repo, 5)

    render_hook(view, "voice_confirm_action", %{})
    assert length(Board.events(repo, 5)) == 1
  end

  test "a changed task invalidates confirmation", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "voice-stale")
    task = task(repo, 8)
    {:ok, view, _} = live(conn, "/?repo=fixture/voice-stale")

    preview(view, "archive task #8")
    task |> Task.changeset(%{state: "blocked"}) |> Repo.update!()
    view |> element("button[phx-click=voice_confirm_action]") |> render_click()

    assert Repo.get!(Task, task.id).state == "blocked"

    assert has_element?(
             view,
             ".voice-command-result[data-kind=error]",
             "Task or repository changed"
           )

    assert Board.events(repo, 5) == []
  end

  test "changing repository clears a pending confirmation", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "voice-original")
    {:ok, _other} = Board.add_repository("fixture", "voice-other")
    task = task(repo, 9)
    {:ok, view, _} = live(conn, "/?repo=fixture/voice-original")

    preview(view, "archive task #9")
    view |> form("#repo-select", %{"repo" => "fixture/voice-other"}) |> render_change()
    refute has_element?(view, ".voice-action-review")
    render_hook(view, "voice_confirm_action", %{})

    assert Repo.get!(Task, task.id).state == "queued"
    assert Board.events(repo, 5) == []
  end

  test "editing the draft clears the pending confirmation", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "voice-edit")
    task = task(repo, 11)
    {:ok, view, _} = live(conn, "/?repo=fixture/voice-edit")

    preview(view, "archive task #11")
    view |> form("#voice-command-form", %{"text" => "status"}) |> render_change()
    refute has_element?(view, ".voice-action-review")
    render_hook(view, "voice_confirm_action", %{})

    assert Repo.get!(Task, task.id).state == "queued"
    assert Board.events(repo, 5) == []
  end

  test "Stop calls GitHub once after confirmation and records the outcome", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "voice-stop")
    task = task(repo, 10)
    parent = self()

    Req.Test.stub(@stub, fn request ->
      send(parent, {request.method, request.request_path})
      Req.Test.json(request, %{"state" => "closed"})
    end)

    {:ok, view, _} = live(conn, "/?repo=fixture/voice-stop")
    preview(view, "stop task #10")
    refute_received {"PATCH", _}
    view |> element("button[phx-click=voice_confirm_action]") |> render_click()

    assert_receive {"PATCH", "/repos/fixture/voice-stop/issues/10"}
    assert Repo.get!(Task, task.id).state == "stopped"

    assert [%{kind: "voice_action", payload: %{"action" => "stop", "result" => "completed"}}] =
             Board.events(repo, 5)

    render_hook(view, "voice_confirm_action", %{})
    refute_received {"PATCH", _}
  end

  test "a rejected GitHub Stop preserves the task and reports failure", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "voice-stop-failure")
    task = task(repo, 12)
    Req.Test.stub(@stub, &Req.Test.json(Plug.Conn.put_status(&1, 500), %{"message" => "failed"}))

    {:ok, view, _} = live(conn, "/?repo=fixture/voice-stop-failure")
    preview(view, "stop task #12")
    view |> element("button[phx-click=voice_confirm_action]") |> render_click()

    assert Repo.get!(Task, task.id).state == "queued"
    assert has_element?(view, ".voice-command-result[data-kind=error]", "Could not stop task #12")

    assert Enum.any?(Board.events(repo, 5), fn event ->
             event.kind == "voice_action" and event.payload["result"] == "failed"
           end)
  end
end
