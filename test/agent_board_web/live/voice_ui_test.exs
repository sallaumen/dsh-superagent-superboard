defmodule AgentBoardWeb.VoiceUITest do
  @moduledoc "The voice section: browse, preview, save and reset."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.Settings

  @stub AgentBoardWeb.VoiceUITest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    Application.put_env(:agent_board, :elevenlabs_client, fn ->
      Req.new(base_url: "https://api.elevenlabs.io", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn -> Application.delete_env(:agent_board, :elevenlabs_client) end)

    :ok
  end

  defp with_key do
    previous = Application.get_env(:agent_board, :elevenlabs_api_key)
    Application.put_env(:agent_board, :elevenlabs_api_key, "test-key")
    on_exit(fn -> Application.put_env(:agent_board, :elevenlabs_api_key, previous) end)
  end

  defp voice_task(repo, title, state) do
    %AgentBoard.Board.Task{}
    |> AgentBoard.Board.Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 42,
      title: title,
      state: state
    })
    |> AgentBoard.Repo.insert!()
  end

  test "without a key the section says so and hides the picker", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "no key"
    assert html =~ "ELEVENLABS_API_KEY"
    refute html =~ "List voices"
  end

  test "browsing lists the account voices", %{conn: conn} do
    with_key()

    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/v1/voices"

      Req.Test.json(conn, %{
        "voices" => [%{"voice_id" => "abc", "name" => "George"}]
      })
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("button", "List voices") |> render_click()

    assert render(view) =~ "George · abc"
  end

  test "picking and saving a voice persists it and plays a confirmation", %{conn: conn} do
    with_key()

    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{
        "voices" => [%{"voice_id" => "abc", "name" => "George"}]
      })
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("button", "List voices") |> render_click()
    view |> element("select[name=voice]") |> render_change(%{"voice" => "abc"})
    view |> element("button", "Save") |> render_click()

    assert Settings.get("elevenlabs_voice_id") == "abc"
    assert render(view) =~ "Voice saved: George"

    assert_push_event(
      view,
      "voice_play",
      %{url: "/api/voice/speech?text=Voice+selected.&voice=abc"}
    )
  end

  test "reset puts the default voice back", %{conn: conn} do
    with_key()
    :ok = Settings.put("elevenlabs_voice_id", "abc")

    {:ok, view, _html} = live(conn, ~p"/")

    assert render(view) =~ "Back to default"

    view |> element("button", "Back to default") |> render_click()

    assert Settings.get("elevenlabs_voice_id") == nil
    assert render(view) =~ "default voice"
  end

  test "changing the model saves it on the spot", %{conn: conn} do
    with_key()

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("select[name=model]") |> render_change(%{"model" => "eleven_v4"})

    assert Settings.get("elevenlabs_tts_model") == "eleven_v4"
    assert render(view) =~ "Model saved: eleven_v4"
    assert render(view) =~ "eleven_v4"
  end

  test "a failed browse keeps the list it already has", %{conn: conn} do
    with_key()

    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"voices" => [%{"voice_id" => "abc", "name" => "George"}]})
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("button", "List voices") |> render_click()
    assert render(view) =~ "George · abc"

    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    view |> element("button", "List voices") |> render_click()

    html = render(view)
    assert html =~ "Could not list voices: HTTP 500"
    assert html =~ "George · abc"
  end

  test "the speak button plays the board status in the agent's voice", %{conn: conn} do
    with_key()

    # The status comes from the model when it can answer; a fixed summary
    # keeps the pushed URL deterministic.
    Application.put_env(:agent_board, :ai_api_key, "test-key")

    Application.put_env(:agent_board, :ai_client, fn ->
      Req.new(base_url: "https://api.deepseek.com", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn ->
      Application.delete_env(:agent_board, :ai_client)
      Application.delete_env(:agent_board, :ai_api_key)
    end)

    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{
        "model" => "deepseek-flash",
        "choices" => [%{"message" => %{"content" => ~s({"summary":"All clear"})}}],
        "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 2}
      })
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    assert render(view) =~ "Falar status"

    view |> element("button", "Falar status") |> render_click()

    assert_push_event(
      view,
      "voice_play",
      %{url: "/api/voice/speech?text=All+clear&voice=JBFqnCBsd6RMkjVDRZzb"}
    )
  end

  test "trying a phrase plays it in the agent's voice", %{conn: conn} do
    with_key()

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#voice-panel form") |> render_submit(%{"phrase" => "Hello agent"})

    assert_push_event(
      view,
      "voice_play",
      %{url: "/api/voice/speech?text=Hello+agent&voice=JBFqnCBsd6RMkjVDRZzb"}
    )
  end

  test "a configured voice still has no click-to-record entrypoint", %{conn: conn} do
    with_key()
    {:ok, _repo} = AgentBoard.Board.add_repository("sallaumen", "arena-rogue")

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#voice-command-shortcut[phx-hook=VoiceCommand]")
    refute has_element?(view, "#voice-dictate")
    refute has_element?(view, "#record-task-title")
    refute has_element?(view, "#ask-by-voice")
  end

  test "without a key the board offers text without browser dictation", %{conn: conn} do
    {:ok, _repo} = AgentBoard.Board.add_repository("sallaumen", "arena-rogue")

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Espaço duas vezes"
    refute html =~ "Dictate task"
    refute html =~ "voice-dictate"
  end

  test "an environment-fixed voice disables the picker", %{conn: conn} do
    with_key()
    Application.put_env(:agent_board, :elevenlabs_voice_id, "env-voice")
    on_exit(fn -> Application.delete_env(:agent_board, :elevenlabs_voice_id) end)

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "env-voice"
    assert html =~ "fixed in .env.local"
    refute html =~ ">Save<"
    refute html =~ "List voices"
  end

  test "an agent state change is spoken", %{conn: conn} do
    with_key()

    {:ok, repo} = AgentBoard.Board.add_repository("sallaumen", "arena-rogue")
    task = voice_task(repo, "Live task", "queued")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    AgentBoard.Repo.update!(AgentBoard.Board.Task.changeset(task, %{state: "running"}))

    send(view.pid, :board_updated)

    assert_push_event(
      view,
      "voice_play",
      %{
        url:
          "/api/voice/speech?text=Task+%27Live+task%27+is+now+running.&voice=JBFqnCBsd6RMkjVDRZzb"
      }
    )
  end

  test "no announcement when the toggle is off", %{conn: conn} do
    with_key()
    :ok = Settings.put("elevenlabs_speak_events", "0")

    {:ok, repo} = AgentBoard.Board.add_repository("sallaumen", "arena-rogue")
    task = voice_task(repo, "Live task", "queued")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    AgentBoard.Repo.update!(AgentBoard.Board.Task.changeset(task, %{state: "running"}))

    send(view.pid, :board_updated)
    refute_receive {_, _, "voice_play", _}, 100
  end

  test "the automatic feedback toggle persists", %{conn: conn} do
    with_key()

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#voice-announce") |> render_change(%{"speak_events" => "false"})
    assert Settings.get("elevenlabs_speak_events") == "0"

    view |> element("#voice-announce") |> render_change(%{"speak_events" => "true"})
    assert Settings.get("elevenlabs_speak_events") == nil
  end

  test "the agent's answer is spoken back", %{conn: conn} do
    with_key()

    {:ok, repo} = AgentBoard.Board.add_repository("sallaumen", "arena-rogue")
    task = voice_task(repo, "Live task", "queued")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    view |> element("#task-#{task.id}") |> render_click()

    send(view.pid, {:answer, task.id, "All good. The sync is clean and nothing is blocked."})

    assert_push_event(
      view,
      "voice_play",
      %{
        url:
          "/api/voice/speech?text=All+good.+The+sync+is+clean+and+nothing+is+blocked.&voice=JBFqnCBsd6RMkjVDRZzb"
      }
    )
  end
end
