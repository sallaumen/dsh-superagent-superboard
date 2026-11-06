defmodule AgentBoardWeb.VoiceAnswerLiveTest do
  @moduledoc "Natural board questions stay read-only and never replace a newer draft."
  use AgentBoardWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias AgentBoard.AI.Call
  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  @stub AgentBoardWeb.VoiceAnswerLiveTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    previous =
      for key <- [:ai_api_key, :ai_provider, :ai_client, :ai_rehearsal], into: %{} do
        {key, Application.get_env(:agent_board, key)}
      end

    Application.put_env(:agent_board, :ai_api_key, "test-key")
    Application.put_env(:agent_board, :ai_provider, :deepseek)
    Application.put_env(:agent_board, :ai_rehearsal, false)

    Application.put_env(:agent_board, :ai_client, fn ->
      Req.new(base_url: "https://api.deepseek.com", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:agent_board, key)
        {key, value} -> Application.put_env(:agent_board, key, value)
      end)
    end)

    :ok
  end

  defp response(answer) do
    %{
      "model" => "deepseek-flash",
      "choices" => [%{"message" => %{"content" => Jason.encode!(%{answer: answer})}}],
      "usage" => %{"prompt_tokens" => 12, "completion_tokens" => 8}
    }
  end

  defp voice_view(conn, owner, name, question) do
    {:ok, _repo} = Board.add_repository(owner, name)
    {:ok, view, _html} = live(conn, "/?repo=#{owner}/#{name}")
    render_hook(view, "voice_transcript", %{"text" => question})
    view
  end

  test "an unknown read question shows a dated AI answer without playing audio", %{conn: conn} do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, response("The saved board has no running task."))
    end)

    view = voice_view(conn, "fixture", "ai-answer", "What is running?")
    view |> form("#voice-command-form", %{"text" => "What is running?"}) |> render_submit()

    assert render_async(view, 1_000) =~ "The saved board has no running task."
    assert has_element?(view, ".voice-command-result[data-kind=ai_answer]", "AI answer")
    assert has_element?(view, ".voice-command-result-source", "Sync time unknown")
    refute_push_event(view, "voice_play", %{url: _})
    assert Repo.aggregate(answer_call_query(), :count) == 1
  end

  test "a completed sync is labeled as the answer's source", %{conn: conn} do
    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, response("The board is saved.")) end)

    {:ok, repo} = Board.add_repository("fixture", "synced-answer")
    {:ok, _event} = Board.log_event(repo.id, "sync", nil, %{"errors" => 0})
    {:ok, view, _html} = live(conn, "/?repo=fixture/synced-answer")
    render_hook(view, "voice_transcript", %{"text" => "What is known?"})
    view |> form("#voice-command-form", %{"text" => "What is known?"}) |> render_submit()

    assert render_async(view, 1_000) =~ "The board is saved."
    assert has_element?(view, "#voice-result-age[data-sync=true]")
    assert has_element?(view, "#voice-result-age", "Last completed sync")
  end

  test "editing the draft discards an older model result", %{conn: conn} do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      send(test_pid, {:ai_started, self()})

      receive do
        :release -> Req.Test.json(conn, response("Outdated answer"))
      after
        3_000 -> Plug.Conn.send_resp(conn, 500, "timeout")
      end
    end)

    view = voice_view(conn, "fixture", "edit-answer", "What is running?")
    view |> form("#voice-command-form", %{"text" => "What is running?"}) |> render_submit()
    assert render(view) =~ "Checking saved board data"
    assert_receive {:ai_started, request_pid}, 1_000

    view |> form("#voice-command-form", %{"text" => "What is blocked?"}) |> render_change()
    send(request_pid, :release)
    render_async(view, 1_000)

    refute render(view) =~ "Outdated answer"
    refute has_element?(view, ".voice-command-result[data-kind=ai_answer]")
    assert has_element?(view, "#voice-command-text", "What is blocked?")
  end

  test "switching repositories discards an older model result", %{conn: conn} do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      send(test_pid, {:ai_started, self()})

      receive do
        :release -> Req.Test.json(conn, response("Wrong repository answer"))
      after
        3_000 -> Plug.Conn.send_resp(conn, 500, "timeout")
      end
    end)

    {:ok, _other} = Board.add_repository("fixture", "other-repo")
    view = voice_view(conn, "fixture", "first-repo", "What is running?")
    view |> form("#voice-command-form", %{"text" => "What is running?"}) |> render_submit()
    assert_receive {:ai_started, request_pid}, 1_000

    render_patch(view, "/?repo=fixture/other-repo&panel=voice")
    send(request_pid, :release)
    render_async(view, 1_000)

    refute render(view) =~ "Wrong repository answer"
    assert has_element?(view, "#voice-command-text")
  end

  test "a new board sync invalidates a pending answer without erasing the draft", %{conn: conn} do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      send(test_pid, {:ai_started, self()})

      receive do
        :release -> Req.Test.json(conn, response("Answer from old snapshot"))
      after
        3_000 -> Plug.Conn.send_resp(conn, 500, "timeout")
      end
    end)

    view = voice_view(conn, "fixture", "updated-answer", "What is running?")
    view |> form("#voice-command-form", %{"text" => "What is running?"}) |> render_submit()
    assert_receive {:ai_started, request_pid}, 1_000

    repo = Board.repository_by_slug("fixture/updated-answer")
    {:ok, _event} = Board.log_event(repo.id, "sync", nil, %{"errors" => 0})
    send(view.pid, :board_updated)

    assert render(view) =~ "Board data changed while the AI was answering"
    send(request_pid, :release)
    render_async(view, 1_000)

    refute render(view) =~ "Answer from old snapshot"
    assert has_element?(view, "#voice-command-text", "What is running?")
  end

  test "a provider failure leaves the draft and shows recovery", %{conn: conn} do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "unavailable") end)

    view = voice_view(conn, "fixture", "failed-answer", "What is running?")
    view |> form("#voice-command-form", %{"text" => "What is running?"}) |> render_submit()

    assert render_async(view, 1_000) =~ "The AI could not answer"
    assert has_element?(view, ".voice-command-result[data-kind=error]")
    assert has_element?(view, "#voice-command-text", "What is running?")
  end

  test "archive history is a board limit without a misleading sync date", %{conn: conn} do
    view = voice_view(conn, "fixture", "archive-limit", "What did you archive today?")

    view
    |> form("#voice-command-form", %{"text" => "What did you archive today?"})
    |> render_submit()

    assert render_async(view, 1_000) =~ "does not include archive history"
    assert has_element?(view, ".voice-command-result[data-kind=board_answer]", "Board data")
    assert has_element?(view, ".voice-command-result-source", "Archive history unavailable")
    refute has_element?(view, "#voice-result-age")
    refute has_element?(view, ".voice-command-result[data-kind=ai_answer]")
    assert Repo.aggregate(answer_call_query(), :count) == 0
    refute_push_event(view, "voice_play", %{url: _})
  end

  test "archive history stays read-only with a conversation open", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "archive-conversation")

    task =
      %Task{}
      |> Task.changeset(%{repository_id: repo.id, number: 17, title: "Keep this task"})
      |> Repo.insert!()

    {:ok, view, _html} =
      live(conn, AgentBoardWeb.BoardNavigation.path(repo, "conversation", task.id))

    for question <- [
          "What did you archive today?",
          "Did you archive anything today?",
          "Você arquivou alguma tarefa hoje?",
          "Which tasks did you archive today?",
          "What did you archive today, and what is running?"
        ] do
      render_hook(view, "voice_transcript", %{"text" => question})
      view |> form("#voice-command-form", %{"text" => question}) |> render_submit()

      html = render_async(view, 1_000)
      assert html =~ "archive history" or html =~ "histórico de arquivamento"
      assert has_element?(view, ".voice-command-result[data-kind=board_answer]")
      refute has_element?(view, "button", "Ask the agent")
    end

    assert Repo.aggregate(answer_call_query(), :count) == 0
    assert Repo.aggregate(AgentBoard.Board.Comment, :count) == 0
  end

  test "a mutation request stays a draft and never calls the model", %{conn: conn} do
    view = voice_view(conn, "fixture", "safe-answer", "Archive task 42")
    view |> form("#voice-command-form", %{"text" => "Archive task 42"}) |> render_submit()

    assert render(view) =~ "Task #42 is not in this repository"
    assert Repo.aggregate(answer_call_query(), :count) == 0
    refute_push_event(view, "voice_play", %{url: _})
  end

  defp answer_call_query, do: from(call in Call, where: call.name == "answer_board_question")
end
