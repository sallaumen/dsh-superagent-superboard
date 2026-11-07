defmodule AgentBoardWeb.VoiceUITest do
  @moduledoc "The voice section: browse, preview, save and reset."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.Settings
  alias AgentBoard.Voice.Phrases

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

  defp spoken(url),
    do: url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("text")

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

    assert html =~ "Sem chave"
    assert html =~ "ELEVENLABS_API_KEY"
    refute html =~ "Listar vozes"
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

    view |> element("button", "Listar vozes") |> render_click()

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

    view |> element("button", "Listar vozes") |> render_click()
    view |> element("#voice-picker-form") |> render_change(%{"voice" => "abc"})
    view |> element("button", "Salvar") |> render_click()

    assert Settings.get("elevenlabs_voice_id") == "abc"
    assert render(view) =~ "Voz salva: George"

    assert_push_event(
      view,
      "voice_play",
      %{url: "/api/voice/stream?text=Voz+escolhida.&voice=abc"}
    )
  end

  test "reset puts the default voice back", %{conn: conn} do
    with_key()
    :ok = Settings.put("elevenlabs_voice_id", "abc")

    {:ok, view, _html} = live(conn, ~p"/")

    assert render(view) =~ "Voltar ao padrão"

    view |> element("button", "Voltar ao padrão") |> render_click()

    assert Settings.get("elevenlabs_voice_id") == nil
    assert render(view) =~ "voz padrão"
  end

  test "changing the model saves it on the spot", %{conn: conn} do
    with_key()

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#voice-model-form") |> render_change(%{"model" => "eleven_v4"})

    assert Settings.get("elevenlabs_tts_model") == "eleven_v4"
    assert render(view) =~ "Modelo salvo: eleven_v4"
    assert render(view) =~ "eleven_v4"
  end

  test "a failed browse keeps the list it already has", %{conn: conn} do
    with_key()

    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"voices" => [%{"voice_id" => "abc", "name" => "George"}]})
    end)

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("button", "Listar vozes") |> render_click()
    assert render(view) =~ "George · abc"

    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    view |> element("button", "Listar vozes") |> render_click()

    html = render(view)
    assert html =~ "Não foi possível listar as vozes: HTTP 500"
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
      %{url: "/api/voice/stream?text=All+clear&voice=JBFqnCBsd6RMkjVDRZzb"}
    )
  end

  test "trying a phrase plays it in the agent's voice", %{conn: conn} do
    with_key()

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#voice-try") |> render_submit(%{"phrase" => "Hello agent"})

    assert_push_event(
      view,
      "voice_play",
      %{url: "/api/voice/stream?text=Hello+agent&voice=JBFqnCBsd6RMkjVDRZzb"}
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
    assert html =~ "definida no .env.local"
    refute html =~ "Salvar"
    refute html =~ "Listar vozes"
  end

  test "an agent state change is spoken", %{conn: conn} do
    with_key()

    {:ok, repo} = AgentBoard.Board.add_repository("sallaumen", "arena-rogue")
    task = voice_task(repo, "Live task", "queued")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    AgentBoard.Repo.update!(AgentBoard.Board.Task.changeset(task, %{state: "running"}))

    send(view.pid, :board_updated)

    assert_push_event(view, "voice_play", %{url: url})

    assert spoken(url) in Enum.map(
             0..2,
             &Phrases.moved("pt-BR", :running, "Live task", &1)
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

    view |> element("#voice-announce-form") |> render_change(%{"speak_events" => "false"})
    assert Settings.get("elevenlabs_speak_events") == "0"

    view |> element("#voice-announce-form") |> render_change(%{"speak_events" => "true"})
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
          "/api/voice/stream?text=All+good.+The+sync+is+clean+and+nothing+is+blocked.&voice=JBFqnCBsd6RMkjVDRZzb"
      }
    )
  end

  test "a task that needs the owner is a call for attention", %{conn: conn} do
    with_key()

    {:ok, repo} = AgentBoard.Board.add_repository("sallaumen", "arena-rogue")
    task = voice_task(repo, "Live task", "running")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    AgentBoard.Repo.update!(AgentBoard.Board.Task.changeset(task, %{state: "blocked"}))
    send(view.pid, :board_updated)

    assert_push_event(view, "voice_play", %{url: url})
    text = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("text")

    assert text in Enum.map(
             0..9,
             &Phrases.attention("pt-BR", :blocked, "Live task", &1)
           )
  end

  test "the attention call still speaks when narration is off", %{conn: conn} do
    with_key()
    :ok = Settings.put("elevenlabs_speak_events", "0")

    {:ok, repo} = AgentBoard.Board.add_repository("sallaumen", "arena-rogue")
    task = voice_task(repo, "Live task", "running")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    AgentBoard.Repo.update!(AgentBoard.Board.Task.changeset(task, %{state: "question"}))
    send(view.pid, :board_updated)

    assert_push_event(view, "voice_play", %{url: "/api/voice/stream?text=" <> _})
  end

  test "without a key the attention call uses the browser voice in the chosen language",
       %{conn: conn} do
    :ok = Settings.put("voice_language", "en-US")

    {:ok, repo} = AgentBoard.Board.add_repository("sallaumen", "arena-rogue")
    task = voice_task(repo, "Live task", "running")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    AgentBoard.Repo.update!(AgentBoard.Board.Task.changeset(task, %{state: "ready"}))
    send(view.pid, :board_updated)

    assert_push_event(view, "speak", %{text: text, lang: "en-US"})
    assert text =~ "Live task"
  end

  test "attention off keeps the owner's calls silent", %{conn: conn} do
    with_key()
    :ok = Settings.put("voice_attention", "0")
    :ok = Settings.put("elevenlabs_speak_events", "0")

    {:ok, repo} = AgentBoard.Board.add_repository("sallaumen", "arena-rogue")
    task = voice_task(repo, "Live task", "running")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    AgentBoard.Repo.update!(AgentBoard.Board.Task.changeset(task, %{state: "blocked"}))
    send(view.pid, :board_updated)

    refute_receive {_, _, "voice_play", _}, 100
  end

  test "the language picker saves and confirms in the new language", %{conn: conn} do
    with_key()

    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#voice-language-form") |> render_change(%{"language" => "en-US"})

    assert Settings.get("voice_language") == "en-US"
    assert render(view) =~ ~s(data-lang="en-US")

    assert_push_event(view, "voice_play", %{
      url:
        "/api/voice/stream?text=Done.+From+now+on+I%27ll+speak+English.&voice=JBFqnCBsd6RMkjVDRZzb"
    })
  end

  test "an unknown language is refused", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#voice-language-form") |> render_change(%{"language" => "xx"})

    assert Settings.get("voice_language") == nil
    assert render(view) =~ "Idioma não suportado"
  end

  test "the volume slider persists and reaches the player", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ ~s(data-volume="100")

    view |> element("#voice-volume-form") |> render_change(%{"volume" => "40"})

    assert Settings.get("voice_volume") == "40"
    html = render(view)
    assert html =~ ~s(data-volume="40")
    assert html =~ "40%"

    # A value outside 0..100 changes nothing.
    view |> element("#voice-volume-form") |> render_change(%{"volume" => "400"})
    assert Settings.get("voice_volume") == "40"
  end

  test "the attention toggle persists", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#voice-attention-form") |> render_change(%{"attention" => "false"})
    assert Settings.get("voice_attention") == "0"

    view |> element("#voice-attention-form") |> render_change(%{"attention" => "true"})
    assert Settings.get("voice_attention") == nil
  end

  test "every voice control changes through a form", %{conn: conn} do
    # The browser refuses phx-change on a control outside a form ("form
    # events require the input to be inside a form"); LiveViewTest does not.
    with_key()
    {:ok, view, _html} = live(conn, ~p"/")

    panel = view |> element("#voice-panel") |> render()
    refute panel =~ ~r/<(input|select)\b[^>]*phx-change/
    assert panel =~ ~r/<form[^>]*phx-change="voice_volume"/
  end

  test "speed, intonation, pause and sounds save from the panel and reach the browser",
       %{conn: conn} do
    with_key()
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ ~s(data-pause-ms="1200")
    assert html =~ ~s(data-earcons="true")

    view |> element("#voice-speed-form") |> render_change(%{"speed" => "1.1"})
    assert Settings.get("voice_speed") == "1.10"
    assert render(view) =~ "1,10×"

    view |> element("#voice-style-form") |> render_change(%{"style" => "expressive"})
    assert Settings.get("voice_style") == "expressive"

    view |> element("#voice-pause-form") |> render_change(%{"pause" => "long"})
    assert render(view) =~ ~s(data-pause-ms="1800")

    view |> element("#voice-earcons-form") |> render_change(%{"earcons" => "false"})
    assert render(view) =~ ~s(data-earcons="false")
  end

  test "the browser voice gets readable text and the saved speed", %{conn: conn} do
    :ok = Settings.put("voice_speed", "0.9")
    {:ok, repo} = AgentBoard.Board.add_repository("sallaumen", "arena-rogue")
    task = voice_task(repo, "Ver **sallaumen/arena-rogue** #7", "running")

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    AgentBoard.Repo.update!(AgentBoard.Board.Task.changeset(task, %{state: "blocked"}))
    send(view.pid, :board_updated)

    assert_push_event(view, "speak", %{text: text, rate: 0.9})
    assert text =~ "Ver arena rogue 7"
    refute text =~ "**"
  end
end
