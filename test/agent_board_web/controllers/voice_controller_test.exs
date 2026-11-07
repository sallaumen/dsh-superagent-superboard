defmodule AgentBoardWeb.VoiceControllerTest do
  @moduledoc "The voice API: status, speech and transcription, stubbed."
  use AgentBoardWeb.ConnCase

  # Failures are exercised on purpose; their log lines show only if a test fails.
  @moduletag capture_log: true

  alias AgentBoard.ElevenLabs.{SpeechCache, Usage}

  @stub AgentBoardWeb.VoiceControllerTest.Stub

  setup do
    # Audio just produced is kept a minute for simultaneous requests: start clean.
    SpeechCache.clear()
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    Application.put_env(:agent_board, :elevenlabs_api_key, "test-key")

    Application.put_env(:agent_board, :elevenlabs_client, fn ->
      Req.new(base_url: "https://api.elevenlabs.io", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn ->
      Application.delete_env(:agent_board, :elevenlabs_client)
      Application.delete_env(:agent_board, :elevenlabs_api_key)
    end)

    :ok
  end

  defp without_key do
    previous = Application.get_env(:agent_board, :elevenlabs_api_key)
    Application.put_env(:agent_board, :elevenlabs_api_key, "")
    on_exit(fn -> Application.put_env(:agent_board, :elevenlabs_api_key, previous) end)
  end

  test "GET /api/voice/status reports the configuration without the key", %{conn: conn} do
    assert %{
             "configured" => true,
             "status" => "logged_in",
             "voice_id" => "JBFqnCBsd6RMkjVDRZzb",
             "voice_source" => "default",
             "tts_model" => "eleven_flash_v2_5",
             "tts_source" => "default",
             "stt_model" => "scribe_v2",
             "speak_events" => true,
             "daily_char_cap" => 20_000,
             "usage" => %{"tts_characters" => 0, "cache_hits" => 0, "stt_seconds" => +0.0}
           } = json_response(get(conn, "/api/voice/status"), 200)
  end

  test "GET /api/voice/status reports today's ElevenLabs usage", %{conn: conn} do
    Usage.record_tts(3420, :paid)
    Usage.record_tts(0, :cache)
    Usage.record_stt(72.0)

    today = Date.to_iso8601(Date.utc_today())

    assert %{
             "usage" => %{
               "day" => ^today,
               "tts_characters" => 3420,
               "tts_requests" => 1,
               "cache_hits" => 1,
               "stt_seconds" => 72.0,
               "stt_requests" => 1
             }
           } = json_response(get(conn, "/api/voice/status"), 200)
  end

  test "GET /api/voice/voices lists the account voices", %{conn: conn} do
    Req.Test.stub(@stub, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/voices"

      Req.Test.json(conn, %{
        "voices" => [
          %{"voice_id" => "abc", "name" => "George"},
          %{"voice_id" => "def", "name" => "Sarah"}
        ]
      })
    end)

    assert %{
             "voices" => [
               %{"id" => "abc", "name" => "George"},
               %{"id" => "def", "name" => "Sarah"}
             ]
           } =
             json_response(get(conn, "/api/voice/voices"), 200)
  end

  test "GET /api/voice/voices maps a rejected key to 401", %{conn: conn} do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 401, "unauthorized") end)

    assert %{"error" => "ElevenLabs rejected the key"} =
             json_response(get(conn, "/api/voice/voices"), 401)
  end

  test "PUT /api/voice/settings stores the picked voice", %{conn: conn} do
    assert %{"voice_id" => "abc", "voice_source" => "saved"} =
             json_response(put(conn, "/api/voice/settings", %{"voice_id" => "abc"}), 200)

    assert AgentBoard.Settings.get("elevenlabs_voice_id") == "abc"
  end

  test "PUT /api/voice/settings stores the picked TTS model", %{conn: conn} do
    assert %{"tts_model" => "eleven_v4", "tts_source" => "saved"} =
             json_response(put(conn, "/api/voice/settings", %{"tts_model" => "eleven_v4"}), 200)

    assert AgentBoard.Settings.get("elevenlabs_tts_model") == "eleven_v4"
  end

  test "PUT /api/voice/settings with neither key is a no-op", %{conn: conn} do
    assert %{"voice_id" => "JBFqnCBsd6RMkjVDRZzb", "tts_model" => "eleven_flash_v2_5"} =
             json_response(put(conn, "/api/voice/settings", %{}), 200)
  end

  test "PUT /api/voice/settings with a blank id clears the pick", %{conn: conn} do
    :ok = AgentBoard.Settings.put("elevenlabs_voice_id", "abc")

    assert %{"voice_id" => "JBFqnCBsd6RMkjVDRZzb", "voice_source" => "default"} =
             json_response(put(conn, "/api/voice/settings", %{"voice_id" => "  "}), 200)

    assert AgentBoard.Settings.get("elevenlabs_voice_id") == nil
  end

  test "PUT /api/voice/settings toggles the automatic speech", %{conn: conn} do
    assert %{"speak_events" => false} =
             json_response(put(conn, "/api/voice/settings", %{"speak_events" => false}), 200)

    assert AgentBoard.Settings.get("elevenlabs_speak_events") == "0"

    assert %{"speak_events" => true} =
             json_response(put(conn, "/api/voice/settings", %{"speak_events" => true}), 200)

    assert AgentBoard.Settings.get("elevenlabs_speak_events") == nil
  end

  test "PUT /api/voice/settings rejects a huge or unknown value", %{conn: conn} do
    assert %{"error" => "a valid voice id is required"} =
             json_response(
               put(conn, "/api/voice/settings", %{"voice_id" => String.duplicate("x", 65)}),
               400
             )

    assert %{"error" => "an offered TTS model is required"} =
             json_response(put(conn, "/api/voice/settings", %{"tts_model" => "not-a-model"}), 400)
  end

  test "PUT /api/voice/settings stores the language, volume and attention", %{conn: conn} do
    assert %{"language" => "pt-BR", "volume" => 100, "attention" => true} =
             json_response(get(conn, "/api/voice/status"), 200)

    assert %{"language" => "en-US", "volume" => 30, "attention" => false} =
             json_response(
               put(conn, "/api/voice/settings", %{
                 "language" => "en-US",
                 "volume" => 30,
                 "attention" => false
               }),
               200
             )

    assert %{"error" => "an offered voice language is required"} =
             json_response(put(conn, "/api/voice/settings", %{"language" => "xx"}), 400)

    assert %{"error" => "the volume must be 0 to 100"} =
             json_response(put(conn, "/api/voice/settings", %{"volume" => 101}), 400)

    assert AgentBoard.Voice.language() == "en-US"
    assert AgentBoard.Voice.volume() == 30
  end

  test "GET /api/voice/speech reads the text in the voice language", %{conn: conn} do
    :ok = AgentBoard.Voice.put_language("en-US")

    Req.Test.stub(@stub, fn conn ->
      assert conn.body_params["language_code"] == "en"
      Plug.Conn.put_resp_content_type(conn, "audio/mpeg") |> Plug.Conn.send_resp(200, "ID3")
    end)

    assert response(get(conn, "/api/voice/speech?text=hi"), 200) == "ID3"
  end

  test "GET /api/voice/stream streams the audio from the streaming endpoint", %{conn: conn} do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/v1/text-to-speech/JBFqnCBsd6RMkjVDRZzb/stream"
      assert conn.body_params["language_code"] == "pt"

      conn
      |> Plug.Conn.put_resp_content_type("audio/mpeg")
      |> Plug.Conn.send_resp(200, "ID3stream")
    end)

    conn = get(conn, "/api/voice/stream?text=oi")

    assert response(conn, 200) == "ID3stream"
    assert get_resp_header(conn, "content-type") == ["audio/mpeg"]
  end

  test "the stream reads the text with the saved speed and intonation", %{conn: conn} do
    :ok = AgentBoard.Voice.put_speed("1.15")
    :ok = AgentBoard.Voice.put_style("steady")

    Req.Test.stub(@stub, fn conn ->
      assert conn.body_params["voice_settings"]["speed"] == 1.15
      assert conn.body_params["voice_settings"]["stability"] == 0.7
      conn |> Plug.Conn.put_resp_content_type("audio/mpeg") |> Plug.Conn.send_resp(200, "ID3")
    end)

    assert response(get(conn, "/api/voice/stream?text=oi"), 200) == "ID3"
  end

  test "PUT /api/voice/settings stores speed, style and pause", %{conn: conn} do
    assert %{"speed" => 0.9, "style" => "expressive", "pause" => "short"} =
             json_response(
               put(conn, "/api/voice/settings", %{
                 "speed" => "0.9",
                 "style" => "expressive",
                 "pause" => "short"
               }),
               200
             )

    assert %{"error" => "the speed must be 0.8 to 1.2"} =
             json_response(put(conn, "/api/voice/settings", %{"speed" => "3"}), 400)
  end

  test "GET /api/voice/stream answers a failure before the first byte as JSON", %{conn: conn} do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 429, "{}") end)

    assert %{"error" => "ElevenLabs usage limit reached"} =
             json_response(get(conn, "/api/voice/stream?text=oi"), 429)
  end

  test "GET /api/voice/stream validates before paying", %{conn: conn} do
    Req.Test.stub(@stub, fn _conn -> flunk("ElevenLabs must not be called") end)

    assert json_response(get(conn, "/api/voice/stream"), 400)
    assert json_response(get(conn, "/api/voice/stream?text=#{String.duplicate("x", 5_001)}"), 400)
  end

  test "a simultaneous request for the same audio waits for the first, without paying twice",
       %{conn: conn} do
    {:ok, calls} = Agent.start_link(fn -> 0 end)
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      Agent.update(calls, &(&1 + 1))
      send(test_pid, :generating)
      Process.sleep(150)

      conn
      |> Plug.Conn.put_resp_content_type("audio/mpeg")
      |> Plug.Conn.send_resp(200, "ID3twice")
    end)

    first = Task.async(fn -> get(conn, "/api/voice/stream?text=Duas+vezes") end)
    assert_receive :generating, 1_000
    second = get(build_conn(), "/api/voice/stream?text=Duas+vezes")

    assert response(second, 200) == "ID3twice"
    assert get_resp_header(second, "x-voice-cache") == ["inflight"]
    assert response(Task.await(first), 200) == "ID3twice"
    assert Agent.get(calls, & &1) == 1
  end

  test "a repeated text is served from the speech cache, once paid", %{conn: conn} do
    Application.put_env(:agent_board, :voice_speech_cache_entries, 10)
    SpeechCache.clear()

    on_exit(fn ->
      Application.put_env(:agent_board, :voice_speech_cache_entries, 0)
      SpeechCache.clear()
    end)

    {:ok, calls} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(@stub, fn conn ->
      Agent.update(calls, &(&1 + 1))
      conn |> Plug.Conn.put_resp_content_type("audio/mpeg") |> Plug.Conn.send_resp(200, "ID3once")
    end)

    assert response(get(conn, "/api/voice/stream?text=Tudo+bem"), 200) == "ID3once"
    second = get(build_conn(), "/api/voice/stream?text=Tudo+bem")
    assert response(second, 200) == "ID3once"
    assert get_resp_header(second, "x-voice-cache") == ["hit"]
    assert Agent.get(calls, & &1) == 1

    # A restart empties the memory; the paid phrase is still not paid again.
    SpeechCache.clear()
    third = get(build_conn(), "/api/voice/stream?text=Tudo+bem")
    assert get_resp_header(third, "x-voice-cache") == ["hit"]
    assert Agent.get(calls, & &1) == 1

    # Paid once (no character header: the text length), hit twice for free.
    assert %{tts_characters: 8, tts_requests: 1, cache_hits: 2} = Usage.today()

    # Another language is another audio: a miss, never the cached one.
    :ok = AgentBoard.Voice.put_language("en-US")
    assert response(get(build_conn(), "/api/voice/stream?text=Tudo+bem"), 200) == "ID3once"
    assert Agent.get(calls, & &1) == 2
  end

  test "GET /api/voice/speech refuses a text that is too long", %{conn: conn} do
    assert %{"error" => "the text is too long for one request"} =
             json_response(
               get(conn, "/api/voice/speech?text=#{String.duplicate("x", 5_001)}"),
               400
             )
  end

  test "GET /api/voice/speech refuses a voice-shaped garbage id", %{conn: conn} do
    assert %{"error" => "a valid voice id is required"} =
             json_response(
               get(conn, "/api/voice/speech?text=hi&voice=#{String.duplicate("x", 65)}"),
               400
             )
  end

  test "GET /api/voice/speech speaks with the voice param", %{conn: conn} do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/v1/text-to-speech/custom-voice"

      Plug.Conn.put_resp_content_type(conn, "audio/mpeg") |> Plug.Conn.send_resp(200, "ID3voice")
    end)

    conn = get(conn, "/api/voice/speech?text=hi&voice=custom-voice")

    assert response(conn, 200) == "ID3voice"
  end

  test "GET /api/voice/status reports not configured without a key", %{conn: conn} do
    without_key()

    assert %{"configured" => false, "status" => "not_configured"} =
             json_response(get(conn, "/api/voice/status"), 200)
  end

  test "GET /api/voice/speech answers a client that accepts audio/mpeg", %{conn: conn} do
    Req.Test.stub(@stub, fn conn ->
      Plug.Conn.put_resp_content_type(conn, "audio/mpeg") |> Plug.Conn.send_resp(200, "ID3audio")
    end)

    conn =
      conn
      |> put_req_header("accept", "audio/mpeg")
      |> get("/api/voice/speech?text=hi")

    assert response(conn, 200) == "ID3audio"
  end

  test "GET /api/voice/speech streams the audio as mp3", %{conn: conn} do
    Req.Test.stub(@stub, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("audio/mpeg")
      |> Plug.Conn.send_resp(200, "ID3fake-audio")
    end)

    conn = get(conn, "/api/voice/speech?text=hello%20board")

    assert response(conn, 200) == "ID3fake-audio"
    assert Enum.at(get_resp_header(conn, "content-type"), 0) =~ "audio/mpeg"
  end

  test "POST /api/voice/speech accepts the text as JSON", %{conn: conn} do
    Req.Test.stub(@stub, fn conn ->
      Plug.Conn.put_resp_content_type(conn, "audio/mpeg") |> Plug.Conn.send_resp(200, "ID3json")
    end)

    conn = post(conn, "/api/voice/speech", %{"text" => "from json"})

    assert response(conn, 200) == "ID3json"
  end

  test "GET /api/voice/speech without a text is 400", %{conn: conn} do
    assert %{"error" => "a text is required"} = json_response(get(conn, "/api/voice/speech"), 400)
  end

  test "GET /api/voice/speech without a key is 503", %{conn: conn} do
    without_key()

    assert %{"error" => "voice not configured"} =
             json_response(get(conn, "/api/voice/speech?text=hi"), 503)
  end

  test "GET /api/voice/speech maps a rejected key to 401", %{conn: conn} do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 401, "unauthorized") end)

    assert %{"error" => "ElevenLabs rejected the key"} =
             json_response(get(conn, "/api/voice/speech?text=hi"), 401)
  end

  test "GET /api/voice/speech maps the usage limit to 429", %{conn: conn} do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 429, "slow down") end)

    assert %{"error" => "ElevenLabs usage limit reached"} =
             json_response(get(conn, "/api/voice/speech?text=hi"), 429)
  end

  test "POST /api/voice/transcribe returns the transcript", %{conn: conn} do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{
        "text" => "cria uma tarefa",
        "language_code" => "por",
        "language_probability" => 0.97,
        "audio_duration_secs" => 2.1
      })
    end)

    conn =
      conn
      |> put_req_header("content-type", "audio/webm")
      |> post("/api/voice/transcribe?language=pt", "fake-audio-bytes")

    assert %{
             "text" => "cria uma tarefa",
             "language_code" => "por",
             "language_probability" => 0.97,
             "audio_duration_secs" => 2.1
           } = json_response(conn, 200)
  end

  test "POST /api/voice/transcribe sends the language hint and the filename", %{conn: conn} do
    Req.Test.stub(@stub, fn conn ->
      assert conn.body_params["language_code"] == "pt"

      %Plug.Upload{filename: "recording.webm"} = upload = conn.body_params["file"]
      assert File.read!(upload.path) == "fake-audio-bytes"

      Req.Test.json(conn, %{"text" => "ok"})
    end)

    conn =
      conn
      |> put_req_header("content-type", "audio/webm")
      |> post("/api/voice/transcribe?language=pt", "fake-audio-bytes")

    assert %{"text" => "ok"} = json_response(conn, 200)
  end

  test "POST /api/voice/transcribe without a body is 400", %{conn: conn} do
    conn = put_req_header(conn, "content-type", "audio/webm")

    assert %{"error" => "an audio body is required"} =
             json_response(post(conn, "/api/voice/transcribe", ""), 400)
  end

  test "POST /api/voice/transcribe without a key is 503", %{conn: conn} do
    without_key()

    conn =
      conn
      |> put_req_header("content-type", "audio/webm")
      |> post("/api/voice/transcribe", "fake-audio-bytes")

    assert %{"error" => "voice not configured"} = json_response(conn, 503)
  end

  test "POST /api/voice/transcribe maps an ElevenLabs error to 502", %{conn: conn} do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    conn = put_req_header(conn, "content-type", "audio/webm")

    assert %{"error" => "ElevenLabs HTTP 500"} =
             json_response(post(conn, "/api/voice/transcribe", "fake-audio-bytes"), 502)
  end

  test "POST /api/voice/transcribe refuses an audio over the cap", %{conn: conn} do
    Application.put_env(:agent_board, :voice_audio_max_bytes, 5)
    on_exit(fn -> Application.delete_env(:agent_board, :voice_audio_max_bytes) end)

    conn = put_req_header(conn, "content-type", "audio/webm")

    assert %{"error" => "the audio is too large"} =
             json_response(post(conn, "/api/voice/transcribe", "0123456789"), 413)
  end
end
