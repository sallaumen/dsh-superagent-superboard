defmodule AgentBoard.Voice.ActivityTest do
  @moduledoc "The live feed of the voice pipeline: broadcast, kept, logged."
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AgentBoard.Voice.Activity

  setup do
    Activity.clear()
    Activity.subscribe()
    :ok
  end

  test "an event is broadcast, kept newest first and logged with its fields" do
    log =
      capture_log([level: :warning], fn ->
        Activity.record(:tts, :retry, "nova tentativa", attempt: 2, reason: {:http, 503}, turn: 7)
        Activity.record(:tts, :ok, "voz gerada", ms: 420)
        Process.sleep(20)
      end)

    assert_received {:voice_activity,
                     %{stage: :tts, status: :retry, detail: "nova tentativa (HTTP 503)"}}

    assert_received {:voice_activity, %{status: :ok, ms: 420}}
    assert [%{status: :ok}, %{status: :retry, turn: 7}] = Activity.recent()
    assert log =~ "voice stage=tts status=retry turn=7 attempt=2 — nova tentativa (HTTP 503)"
  end

  test "reasons read as words" do
    assert Activity.reason(:usage_limit) == "usage limit (429)"
    assert Activity.reason({:http, 502}) == "HTTP 502"
    assert Activity.reason(%Req.TransportError{reason: :timeout}) =~ "timeout"
  end
end
