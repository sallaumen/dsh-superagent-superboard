defmodule AgentBoard.ElevenLabs.SpeechCacheTest do
  @moduledoc """
  The spoken-audio cache: keyed by every input, bounded, durable across a
  restart (an emptied ETS table), expired after 30 days, off in tests by
  default.
  """
  use AgentBoard.DataCase, async: false

  import Ecto.Query

  alias AgentBoard.ElevenLabs.SpeechCache

  setup do
    Application.put_env(:agent_board, :voice_speech_cache_entries, 2)
    SpeechCache.clear()

    on_exit(fn ->
      Application.put_env(:agent_board, :voice_speech_cache_entries, 0)
      Application.delete_env(:agent_board, :voice_speech_cache_rows)
      SpeechCache.clear()
    end)
  end

  defp rows, do: Repo.all(from r in "voice_speech_cache", select: r.key) |> Enum.sort()

  test "the key changes with any option that changes the audio" do
    base = SpeechCache.key("oi", voice: "a", model: "m", language: "pt")
    assert base == SpeechCache.key("oi", language: "pt", model: "m", voice: "a")
    refute base == SpeechCache.key("oi", voice: "b", model: "m", language: "pt")
    refute base == SpeechCache.key("oi", voice: "a", model: "m", language: "en")
    refute base == SpeechCache.key("oi", voice: "a", model: "m", language: "pt", speed: 1.1)
  end

  test "stores short texts, skips long ones and drops the oldest from memory when full" do
    SpeechCache.put("k1", "um", "a1")
    SpeechCache.put("long", String.duplicate("x", 301), "big")
    assert SpeechCache.get("k1") == {:ok, "a1"}
    assert SpeechCache.get("long") == :miss
    refute "long" in rows()

    Process.sleep(5)
    SpeechCache.put("k2", "dois", "a2")
    SpeechCache.put("k3", "três", "a3")

    # Out of memory, still in the table: served without paying again.
    assert :ets.lookup(SpeechCache, "k1") == []
    assert SpeechCache.get("k1") == {:ok, "a1"}
    assert SpeechCache.get("k3") == {:ok, "a3"}
  end

  test "a paid phrase survives a restart (the memory layer emptied)" do
    SpeechCache.put("fixed", "Tudo certo.", "ID3fixed")
    SpeechCache.clear()

    assert :ets.lookup(SpeechCache, "fixed") == []
    assert SpeechCache.get("fixed") == {:ok, "ID3fixed"}
    # The hit goes back to memory: the next one reads no row.
    assert [{"fixed", "ID3fixed", _at}] = :ets.lookup(SpeechCache, "fixed")
  end

  test "a row unused for 30 days is a miss and is pruned by the next write" do
    SpeechCache.put("old", "velho", "ID3old")
    SpeechCache.clear()
    old = DateTime.add(DateTime.utc_now(), -31 * 24 * 3600, :second)

    Repo.update_all(from(r in "voice_speech_cache", where: r.key == "old"),
      set: [last_used_at: old]
    )

    assert SpeechCache.get("old") == :miss
    SpeechCache.put("new", "novo", "ID3new")
    assert rows() == ["new"]
  end

  test "the table keeps only the most recently used rows" do
    Application.put_env(:agent_board, :voice_speech_cache_rows, 2)

    for key <- ~w(r1 r2 r3) do
      SpeechCache.put(key, key, "ID3" <> key)
      Process.sleep(2)
    end

    assert rows() == ["r2", "r3"]
  end

  test "zero entries turns it off, in memory and in the table" do
    Application.put_env(:agent_board, :voice_speech_cache_entries, 0)
    SpeechCache.put("k", "oi", "audio")
    assert SpeechCache.get("k") == :miss
    assert rows() == []
  end
end
