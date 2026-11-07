defmodule AgentBoard.ElevenLabs.SpeechCacheTest do
  @moduledoc "The spoken-audio cache: keyed by every input, bounded, off in tests by default."
  use ExUnit.Case, async: false

  alias AgentBoard.ElevenLabs.SpeechCache

  setup do
    Application.put_env(:agent_board, :voice_speech_cache_entries, 2)
    SpeechCache.clear()

    on_exit(fn ->
      Application.put_env(:agent_board, :voice_speech_cache_entries, 0)
      SpeechCache.clear()
    end)
  end

  test "the key changes with any option that changes the audio" do
    base = SpeechCache.key("oi", voice: "a", model: "m", language: "pt")
    assert base == SpeechCache.key("oi", language: "pt", model: "m", voice: "a")
    refute base == SpeechCache.key("oi", voice: "b", model: "m", language: "pt")
    refute base == SpeechCache.key("oi", voice: "a", model: "m", language: "en")
    refute base == SpeechCache.key("oi", voice: "a", model: "m", language: "pt", speed: 1.1)
  end

  test "stores short texts, skips long ones and drops the oldest when full" do
    SpeechCache.put("k1", "um", "a1")
    SpeechCache.put("long", String.duplicate("x", 301), "big")
    assert SpeechCache.get("k1") == {:ok, "a1"}
    assert SpeechCache.get("long") == :miss

    Process.sleep(5)
    SpeechCache.put("k2", "dois", "a2")
    SpeechCache.put("k3", "três", "a3")

    assert SpeechCache.get("k1") == :miss
    assert SpeechCache.get("k3") == {:ok, "a3"}
  end

  test "zero entries turns it off" do
    Application.put_env(:agent_board, :voice_speech_cache_entries, 0)
    SpeechCache.put("k", "oi", "audio")
    assert SpeechCache.get("k") == :miss
  end
end
