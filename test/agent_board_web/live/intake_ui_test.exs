defmodule AgentBoardWeb.IntakeUITest do
  @moduledoc "The Split form shows the spec and the tasks before anything is created."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.Board

  @stub AgentBoardWeb.IntakeUITest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    Application.put_env(:agent_board, :ai_api_key, "test-key")

    Application.put_env(:agent_board, :ai_client, fn ->
      Req.new(base_url: "https://api.deepseek.com", plug: {Req.Test, @stub}, retry: false)
    end)

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn ->
      Application.delete_env(:agent_board, :ai_client)
      Application.delete_env(:agent_board, :ai_api_key)
      Application.delete_env(:agent_board, :github_client)
    end)

    :ok
  end

  defp answer(content) do
    %{
      "model" => "deepseek-flash",
      "choices" => [%{"message" => %{"content" => content}}],
      "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 2}
    }
  end

  test "the ask shows the model's answer", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %AgentBoard.Board.Task{}
    |> AgentBoard.Board.Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 901,
      title: "Board lento",
      state: "queued"
    })
    |> AgentBoard.Repo.insert!()

    Req.Test.stub(@stub, fn conn ->
      if String.ends_with?(conn.request_path, "/chat/completions") do
        Req.Test.json(conn, answer(~s({"answer":"O sync roda a cada minuto."})))
      else
        Req.Test.json(conn, %{"id" => 1, "user" => %{"login" => "sallaumen"}})
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    view |> element("button", "Open") |> render_click()

    html = view |> element("#ask-agent") |> render_submit(%{"body" => "por que demora?"})
    assert html =~ "Question sent"

    # the model answers on another process: let it land, then render
    Process.sleep(150)
    assert render(view) =~ "O sync roda a cada minuto."
  end

  test "the panel says when the AI is not configured", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")
    Application.put_env(:agent_board, :ai_api_key, "")

    {:ok, view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert has_element?(view, "#intake-form button[disabled]")
    assert html =~ "not configured"
    assert html =~ "No AI calls recorded yet."
    assert html =~ "Split is unavailable"
  end

  test "failed creation reports one error and never a success", %{conn: conn} do
    {:ok, _} = Board.add_repository("fixture", "actions")

    Req.Test.stub(
      @stub,
      &Req.Test.json(Plug.Conn.put_status(&1, 422), %{"message" => "rejected"})
    )

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/actions")

    view |> element("#create-task") |> render_submit(%{"title" => "Fixture", "body" => ""})

    assert has_element?(view, "#flash-error", "Could not create the task")
    refute has_element?(view, "#flash-info")
    assert length(Regex.scan(~r/Could not create the task/, render(view))) == 1
    refute render(view) =~ "Task created"
  end

  test "successful creation reports success", %{conn: conn} do
    {:ok, _} = Board.add_repository("fixture", "actions")

    Req.Test.stub(
      @stub,
      &Req.Test.json(&1, %{"number" => 123, "html_url" => "https://example.test/issues/123"})
    )

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/actions")

    view |> element("#create-task") |> render_submit(%{"title" => "Fixture", "body" => ""})

    assert has_element?(view, "#flash-info", "Task created")
    refute has_element?(view, "#flash-error")
  end

  test "the form shows the goal, the open questions and the tasks", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      content =
        if Enum.any?(payload["messages"], &String.contains?(&1["content"], "Specification")) do
          ~s({"tasks":[{"title":"medir o tempo","body":"mede","kind":"bug","acceptance":["p95"],"depends_on":[],"size":"S"}]})
        else
          ~s({"goal":"o board responde rapido","constraints":[],"non_goals":[],"risks":[],"open_questions":[],"assumptions":[],"ready":true,"language":"pt"})
        end

      Req.Test.json(conn, answer(content))
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    html = view |> element("#intake-form") |> render_submit(%{"text" => "o board ta lento"})

    assert html =~ "o board responde rapido"
    assert html =~ "medir o tempo"
    assert html =~ "Latest 2 calls across the board."
    assert html =~ "refine_request"

    {:ok, _} = Board.add_repository("fixture", "other")
    view |> element("#repo-select") |> render_change(%{"repo" => "fixture/other"})
    refute render(view) =~ "medir o tempo"
  end

  test "a voice request opens an editable draft without splitting or creating anything", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "voice-intake")
    {:ok, view, _html} = live(conn, "/?repo=fixture/voice-intake")

    render_hook(view, "voice_prepare_intake", %{"text" => "  Build a status view  "})

    assert_patch(view, "/?panel=intake&repo=fixture%2Fvoice-intake")
    assert has_element?(view, "#intake-voice-draft")
    assert has_element?(view, "#intake-repository", "fixture/voice-intake")
    assert has_element?(view, "#intake-form input[name=source_repo][value='#{repo.id}']")
    assert render(view) =~ "Build a status view"
    assert AgentBoard.AI.recent(5) == []
    assert AgentBoard.Repo.aggregate(AgentBoard.Board.Task, :count, :id) == 0

    view
    |> element("#intake-form")
    |> render_change(%{
      "text" => "Build a clearer status view",
      "source_repo" => to_string(repo.id)
    })

    send(view.pid, :board_updated)
    assert render(view) =~ "Build a clearer status view"
    assert AgentBoard.AI.recent(5) == []
  end

  test "the voice panel prepares the edited command in the selected repository", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "voice-action")
    {:ok, view, _html} = live(conn, "/?repo=fixture/voice-action")

    render_hook(view, "voice_transcript", %{"text" => "Original spoken request"})
    assert_patch(view, "/?panel=voice&repo=fixture%2Fvoice-action")

    view
    |> element("#voice-command-form")
    |> render_change(%{"text" => "Edited coding request"})

    assert has_element?(view, "#voice-prepare-intake[name=mode][value=intake]")

    view
    |> element("#voice-command-form")
    |> render_submit(%{"text" => "Edited coding request", "mode" => "intake"})

    assert_patch(view, "/?panel=intake&repo=fixture%2Fvoice-action")
    assert has_element?(view, "#intake-form input[name=source_repo][value='#{repo.id}']")
    assert render(view) =~ "Edited coding request"
    assert AgentBoard.AI.recent(5) == []
    assert AgentBoard.Repo.aggregate(AgentBoard.Board.Task, :count, :id) == 0
  end

  test "a voice draft cannot be split after the selected repository changes", %{conn: conn} do
    {:ok, original} = Board.add_repository("fixture", "original")
    {:ok, _other} = Board.add_repository("fixture", "other")
    {:ok, view, _html} = live(conn, "/?repo=fixture/original")

    render_hook(view, "voice_prepare_intake", %{"text" => "Build something"})
    view |> element("#repo-select") |> render_change(%{"repo" => "fixture/other"})

    refute has_element?(view, "#intake-voice-draft")

    html =
      view
      |> element("#intake-form")
      |> render_submit(%{"text" => "Build something", "source_repo" => to_string(original.id)})

    assert html =~ "Repository changed. Review the request again."
    assert AgentBoard.AI.recent(5) == []
  end
end
