defmodule AgentBoard.ElevenLabs.SpeechCache do
  @moduledoc """
  Spoken audio for a text the board already paid for, kept in memory.

  The agent repeats itself on purpose (the attention calls rotate through a
  fixed pool, confirmations and errors are fixed sentences), so a repeat is
  served at once and costs nothing. The key is every input that changes the
  audio (text, voice, model, language and voice settings): changing any of
  them is a miss, never a stale voice. Only short texts are kept, the table is
  bounded (`:voice_speech_cache_entries`, 0 disables it) and an entry lives a
  week; the oldest goes first when it is full. A restart empties it.
  """
  use GenServer

  @table __MODULE__
  @max_text 300
  @ttl_ms 7 * 24 * 3600 * 1000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  @doc "The cache key for a text and the options that shape its audio."
  @spec key(String.t(), keyword()) :: binary()
  def key(text, opts) do
    :crypto.hash(:sha256, :erlang.term_to_binary({text, Enum.sort(opts)}))
  end

  @doc "Audio stored for the key, unless it expired or the cache is off."
  @spec get(binary()) :: {:ok, binary()} | :miss
  def get(key) do
    with true <- enabled?(),
         [{^key, audio, at}] <- :ets.lookup(@table, key),
         true <- now() - at < @ttl_ms do
      {:ok, audio}
    else
      _ -> :miss
    end
  end

  @doc "Stores the audio of a short text; a long one is not worth the memory."
  @spec put(binary(), String.t(), binary()) :: :ok
  def put(key, text, audio) when is_binary(audio) and byte_size(audio) > 0 do
    if enabled?() and String.length(text) <= @max_text do
      evict_if_full()
      :ets.insert(@table, {key, audio, now()})
    end

    :ok
  end

  def put(_key, _text, _audio), do: :ok

  @doc "Empties the cache."
  def clear do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  defp evict_if_full do
    if :ets.info(@table, :size) >= max_entries(), do: evict_oldest()
  end

  defp evict_oldest do
    case :ets.select(@table, [{{:"$1", :_, :"$2"}, [], [{{:"$2", :"$1"}}]}]) do
      [] -> :ok
      entries -> :ets.delete(@table, entries |> Enum.min() |> elem(1))
    end
  end

  defp enabled?, do: max_entries() > 0 and :ets.whereis(@table) != :undefined

  defp max_entries, do: Application.get_env(:agent_board, :voice_speech_cache_entries, 150)

  defp now, do: System.system_time(:millisecond)
end
