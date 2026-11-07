defmodule AgentBoard.ElevenLabsTest do
  @moduledoc "The ElevenLabs voice client: speech, transcription, voices, failures."
  use AgentBoard.DataCase, async: false

  # Failures are exercised on purpose; their log lines show only if a test fails.
  @moduletag capture_log: true

  alias AgentBoard.ElevenLabs
  alias AgentBoard.Settings

  @stub AgentBoard.ElevenLabsTest.Stub

  setup do
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

  defp audio(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("audio/mpeg")
    |> Plug.Conn.put_resp_header("x-character-count", "12")
    |> Plug.Conn.put_resp_header("request-id", "req-1")
    |> Plug.Conn.send_resp(200, body)
  end

  test "status is not_configured without a key" do
    previous = Application.get_env(:agent_board, :elevenlabs_api_key)
    Application.put_env(:agent_board, :elevenlabs_api_key, "")
    on_exit(fn -> Application.put_env(:agent_board, :elevenlabs_api_key, previous) end)

    refute ElevenLabs.configured?()
    assert ElevenLabs.status() == :not_configured
  end

  test "status is logged_in with a key" do
    assert ElevenLabs.configured?()
    assert ElevenLabs.status() == :logged_in
  end

  test "the defaults are the documented voice and models" do
    assert ElevenLabs.voice_id() == "JBFqnCBsd6RMkjVDRZzb"
    assert ElevenLabs.voice_source() == :default
    assert ElevenLabs.tts_model() == "eleven_flash_v2_5"
    assert ElevenLabs.tts_source() == :default
    assert ElevenLabs.stt_model() == "scribe_v2"
  end

  test "a saved voice wins over the default" do
    :ok = Settings.put("elevenlabs_voice_id", "saved-voice")

    assert ElevenLabs.voice_id() == "saved-voice"
    assert ElevenLabs.voice_source() == :saved
  end

  test "a saved TTS model wins over the default" do
    :ok = Settings.put("elevenlabs_tts_model", "eleven_v4")

    assert ElevenLabs.tts_model() == "eleven_v4"
    assert ElevenLabs.tts_source() == :saved
  end

  test "the environment voice wins over the saved one" do
    :ok = Settings.put("elevenlabs_voice_id", "saved-voice")
    Application.put_env(:agent_board, :elevenlabs_voice_id, "env-voice")
    on_exit(fn -> Application.delete_env(:agent_board, :elevenlabs_voice_id) end)

    assert ElevenLabs.voice_id() == "env-voice"
    assert ElevenLabs.voice_source() == :environment
  end

  test "the environment model wins over the saved one" do
    :ok = Settings.put("elevenlabs_tts_model", "eleven_v4")
    Application.put_env(:agent_board, :elevenlabs_tts_model, "eleven_multilingual_v2")
    on_exit(fn -> Application.delete_env(:agent_board, :elevenlabs_tts_model) end)

    assert ElevenLabs.tts_model() == "eleven_multilingual_v2"
    assert ElevenLabs.tts_source() == :environment
  end

  test "the environment overrides the defaults" do
    Application.put_env(:agent_board, :elevenlabs_voice_id, "custom-voice")
    on_exit(fn -> Application.delete_env(:agent_board, :elevenlabs_voice_id) end)

    assert ElevenLabs.voice_id() == "custom-voice"
  end

  test "a nil app config falls back to the default" do
    Application.put_env(:agent_board, :elevenlabs_tts_model, nil)
    on_exit(fn -> Application.delete_env(:agent_board, :elevenlabs_tts_model) end)

    assert ElevenLabs.tts_model() == "eleven_flash_v2_5"
  end

  test "voice ids and texts are validated before they travel" do
    assert ElevenLabs.valid_voice_id?("abc-voice")
    assert ElevenLabs.valid_voice_id?("  abc  ")
    refute ElevenLabs.valid_voice_id?("")
    refute ElevenLabs.valid_voice_id?("   ")
    refute ElevenLabs.valid_voice_id?(String.duplicate("x", 65))
    refute ElevenLabs.valid_voice_id?(nil)

    assert ElevenLabs.valid_text?("hello")
    refute ElevenLabs.valid_text?(String.duplicate("x", 5_001))
    refute ElevenLabs.valid_text?(nil)
  end

  test "the TTS model catalog is the picker's contract" do
    models = ElevenLabs.tts_models()

    assert Enum.any?(models, &(&1.id == "eleven_flash_v2_5"))
    assert Enum.any?(models, &(&1.id == "eleven_v4"))

    assert ElevenLabs.valid_tts_model?("eleven_flash_v2_5")
    refute ElevenLabs.valid_tts_model?("not-a-model")
  end

  test "the built client carries the key as xi-api-key" do
    Application.put_env(:agent_board, :elevenlabs_api_key, "test-key")
    on_exit(fn -> Application.delete_env(:agent_board, :elevenlabs_api_key) end)

    assert Req.Request.get_header(ElevenLabs.build(), "xi-api-key") == ["test-key"]
  end

  test "the built client has no key header without a key" do
    previous = Application.get_env(:agent_board, :elevenlabs_api_key)
    Application.put_env(:agent_board, :elevenlabs_api_key, "")
    on_exit(fn -> Application.put_env(:agent_board, :elevenlabs_api_key, previous) end)

    assert Req.Request.get_header(ElevenLabs.build(), "xi-api-key") == []
  end

  test "speech posts the text to the voice and returns the audio" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/text-to-speech/JBFqnCBsd6RMkjVDRZzb"
      assert conn.query_string =~ "output_format=mp3_44100_128"
      assert conn.query_string =~ "optimize_streaming_latency=3"

      assert conn.body_params["text"] == "hello board"
      assert conn.body_params["model_id"] == "eleven_flash_v2_5"
      assert conn.body_params["voice_settings"]["stability"] == 0.5
      assert conn.body_params["voice_settings"]["similarity_boost"] == 0.75

      audio(conn, <<0, 1, 2, 3>>)
    end)

    assert {:ok,
            %{
              audio: <<0, 1, 2, 3>>,
              format: "mp3_44100_128",
              characters: 12,
              request_id: "req-1"
            }} = ElevenLabs.speech("hello board")
  end

  test "speech passes the voice, model and settings from the options" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/v1/text-to-speech/custom-voice"
      assert conn.body_params["model_id"] == "eleven_v4"
      assert conn.body_params["voice_settings"]["stability"] == 0.8
      assert conn.body_params["voice_settings"]["similarity_boost"] == 0.9

      Plug.Conn.put_resp_content_type(conn, "audio/mpeg") |> Plug.Conn.send_resp(200, <<1, 2>>)
    end)

    assert {:ok, %{audio: <<1, 2>>, characters: nil}} =
             ElevenLabs.speech("hi",
               voice: "custom-voice",
               model: "eleven_v4",
               stability: 0.8,
               similarity_boost: 0.9
             )
  end

  test "speech enforces the language only on the models that accept it" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.body_params["language_code"] == "pt"
      Plug.Conn.put_resp_content_type(conn, "audio/mpeg") |> Plug.Conn.send_resp(200, <<1>>)
    end)

    assert {:ok, _} = ElevenLabs.speech("oi", language: "pt")

    # v4 infers the language from the text; the field would be a 400 there.
    Req.Test.stub(@stub, fn conn ->
      refute Map.has_key?(conn.body_params, "language_code")
      Plug.Conn.put_resp_content_type(conn, "audio/mpeg") |> Plug.Conn.send_resp(200, <<1>>)
    end)

    assert {:ok, _} = ElevenLabs.speech("oi", language: "pt", model: "eleven_v4")
  end

  test "speech sends the speed only when asked for" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.body_params["voice_settings"]["speed"] == 1.1
      assert conn.body_params["voice_settings"]["stability"] == 0.3
      Plug.Conn.put_resp_content_type(conn, "audio/mpeg") |> Plug.Conn.send_resp(200, <<1>>)
    end)

    assert {:ok, _} = ElevenLabs.speech("oi", speed: 1.1, stability: 0.3)

    Req.Test.stub(@stub, fn conn ->
      refute Map.has_key?(conn.body_params["voice_settings"], "speed")
      Plug.Conn.put_resp_content_type(conn, "audio/mpeg") |> Plug.Conn.send_resp(200, <<1>>)
    end)

    assert {:ok, _} = ElevenLabs.speech("oi")
  end

  test "speech maps the paid failures to reasons" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 401, "unauthorized") end)
    assert {:error, :auth_expired} = ElevenLabs.speech("hi")

    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 429, "slow down") end)
    assert {:error, :usage_limit} = ElevenLabs.speech("hi")

    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
    assert {:error, {:http, 500}} = ElevenLabs.speech("hi")
  end

  test "speech without a key never reaches the network" do
    previous = Application.get_env(:agent_board, :elevenlabs_api_key)
    Application.put_env(:agent_board, :elevenlabs_api_key, "")
    on_exit(fn -> Application.put_env(:agent_board, :elevenlabs_api_key, previous) end)

    Req.Test.stub(@stub, fn _conn -> raise "the network must not be reached" end)

    assert {:error, :not_configured} = ElevenLabs.speech("hi")
  end

  test "transcribe uploads the audio and returns the transcript" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/speech-to-text"
      assert conn.body_params["model_id"] == "scribe_v2"

      %Plug.Upload{filename: "recording.webm"} = upload = conn.body_params["file"]
      assert File.read!(upload.path) == "fake-audio-bytes"

      Req.Test.json(conn, %{
        "text" => "olá mundo",
        "language_code" => "por",
        "language_probability" => 0.99,
        "audio_duration_secs" => 1.5
      })
    end)

    assert {:ok,
            %{
              text: "olá mundo",
              language_code: "por",
              language_probability: 0.99,
              audio_duration_secs: 1.5
            }} = ElevenLabs.transcribe("fake-audio-bytes", "recording.webm")
  end

  test "transcribe passes the language hint and keyterms" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.body_params["language_code"] == "pt"
      assert "agent-board" in List.wrap(conn.body_params["keyterms"])

      Req.Test.json(conn, %{"text" => "tudo pronto"})
    end)

    assert {:ok, %{text: "tudo pronto"}} =
             ElevenLabs.transcribe("fake-audio", "recording.webm",
               language: "pt",
               keyterms: ["agent-board"]
             )
  end

  test "transcribe maps the failures to reasons" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 401, "unauthorized") end)
    assert {:error, :auth_expired} = ElevenLabs.transcribe("x", "x.webm")

    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 422, "bad model") end)
    assert {:error, {:http, 422}} = ElevenLabs.transcribe("x", "x.webm")
  end

  test "voices lists the account voices" do
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

    assert {:ok, [%{id: "abc", name: "George"}, %{id: "def", name: "Sarah"}]} =
             ElevenLabs.voices()
  end

  test "voices maps a rejection to a reason" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 401, "unauthorized") end)
    assert {:error, :auth_expired} = ElevenLabs.voices()
  end

  test "automatic speech defaults on and the settings can turn it off" do
    assert ElevenLabs.speak_events?()

    :ok = Settings.put("elevenlabs_speak_events", "0")
    refute ElevenLabs.speak_events?()

    :ok = Settings.put("elevenlabs_speak_events", "")
    assert ElevenLabs.speak_events?()
  end

  test "the voices list is cached within its ttl" do
    previous_ttl = Application.get_env(:agent_board, :voice_voices_ttl)
    Application.put_env(:agent_board, :voice_voices_ttl, 60_000)

    on_exit(fn ->
      Application.put_env(:agent_board, :voice_voices_ttl, previous_ttl)
      :persistent_term.erase({AgentBoard.ElevenLabs, :voices})
    end)

    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(@stub, fn conn ->
      Agent.update(counter, &(&1 + 1))

      Req.Test.json(conn, %{"voices" => [%{"voice_id" => "abc", "name" => "George"}]})
    end)

    assert {:ok, voices} = ElevenLabs.voices()
    assert {:ok, ^voices} = ElevenLabs.voices()

    assert Agent.get(counter, & &1) == 1
  end
end
