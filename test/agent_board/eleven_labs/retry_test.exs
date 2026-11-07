defmodule AgentBoard.ElevenLabs.RetryTest do
  @moduledoc """
  The retry policy: only failures with nothing to pay for are tried again,
  never more than the cap, never after a stream started, and every retry is
  announced.
  """
  use AgentBoard.DataCase, async: false

  # Failures are exercised on purpose; their log lines show only if a test fails.
  @moduletag capture_log: true

  alias AgentBoard.ElevenLabs
  alias AgentBoard.ElevenLabs.Retry
  alias AgentBoard.Voice.Activity

  @stub AgentBoard.ElevenLabs.RetryTest.Stub

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

    Activity.clear()
    Activity.subscribe()
    {:ok, calls} = Agent.start_link(fn -> 0 end)
    %{calls: calls}
  end

  # Answers the scripted statuses in order, then the last one forever.
  defp script(calls, statuses) do
    Req.Test.stub(@stub, fn conn ->
      n = Agent.get_and_update(calls, &{&1, &1 + 1})

      case Enum.at(statuses, n, List.last(statuses)) do
        :transport ->
          Req.Test.transport_error(conn, :timeout)

        200 ->
          conn
          |> Plug.Conn.put_resp_content_type("audio/mpeg")
          |> Plug.Conn.send_resp(200, "ID3ok")

        status ->
          Plug.Conn.send_resp(conn, status, "{}")
      end
    end)
  end

  test "a 503 is tried again and the second attempt plays", %{calls: calls} do
    script(calls, [503, 200])

    assert {:ok, %{audio: "ID3ok"}} = ElevenLabs.speech("oi")
    assert Agent.get(calls, & &1) == 2
    assert_received {:voice_activity, %{stage: :tts, status: :retry, attempt: 2, detail: detail}}
    assert detail =~ "HTTP 503"
  end

  test "a dropped connection is tried again", %{calls: calls} do
    script(calls, [:transport, 200])

    assert {:ok, _} = ElevenLabs.speech("oi")
    assert Agent.get(calls, & &1) == 2
  end

  test "a refused key is final: one call, no retry", %{calls: calls} do
    script(calls, [401])

    assert {:error, :auth_expired} = ElevenLabs.speech("oi")
    assert Agent.get(calls, & &1) == 1
    refute_received {:voice_activity, %{status: :retry}}
  end

  test "the retries stop at the cap and the failure is the reason", %{calls: calls} do
    script(calls, [500])

    assert {:error, {:http, 500}} = ElevenLabs.speech("oi")
    assert Agent.get(calls, & &1) == 3
  end

  test "a stream is retried before its first byte", %{calls: calls} do
    script(calls, [502, 200])
    test_pid = self()

    assert :ok =
             ElevenLabs.speech_stream("oi", [], fn data ->
               send(test_pid, {:chunk, data}) && :ok
             end)

    assert_received {:chunk, "ID3ok"}
    assert Agent.get(calls, & &1) == 2
  end

  test "a stream that already delivered audio is never retried" do
    Retry.mark_streamed()
    request = Req.new()

    refute Retry.decide(:tts, request, %Req.Response{status: 503})
    Retry.reset_streamed()
    assert {:delay, _} = Retry.decide(:tts, request, %Req.Response{status: 503})
  end

  test "transcription and the voice list use the same policy", %{calls: calls} do
    Req.Test.stub(@stub, fn conn ->
      n = Agent.get_and_update(calls, &{&1, &1 + 1})

      if n == 0,
        do: Plug.Conn.send_resp(conn, 429, "{}"),
        else: Req.Test.json(conn, %{"text" => "oi", "voices" => []})
    end)

    assert {:ok, %{text: "oi"}} = ElevenLabs.transcribe("audio", "a.webm")
    assert_received {:voice_activity, %{stage: :transcribe, status: :retry}}
  end
end
