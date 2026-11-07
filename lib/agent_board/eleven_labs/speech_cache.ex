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

  It also deduplicates requests in flight: WebKit opens a second request for
  the same audio while the first is still streaming, which paid ElevenLabs
  twice. The first request `claim/1`s the key; a second one `await/2`s it
  and is served the same bytes, kept briefly (`release/2`) whatever their
  length.
  """
  use GenServer

  @table __MODULE__
  @max_text 300
  @ttl_ms 7 * 24 * 3600 * 1000
  @inflight_ms 30_000
  @recent_ms 60_000
  @poll_ms 40

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

  @doc "Audio stored for the key (or just produced for it), unless expired."
  @spec get(binary()) :: {:ok, binary()} | :miss
  def get(key) do
    case recent(key) do
      {:ok, audio} -> {:ok, audio}
      :miss -> cached(key)
    end
  end

  defp cached(key) do
    with true <- enabled?(),
         [{^key, audio, at}] <- :ets.lookup(@table, key),
         true <- now() - at < @ttl_ms do
      {:ok, audio}
    else
      _ -> :miss
    end
  end

  defp recent(key) do
    with true <- table?(),
         [{_, audio, at}] <- :ets.lookup(@table, {:recent, key}),
         true <- now() - at < @recent_ms do
      {:ok, audio}
    else
      _ -> :miss
    end
  end

  @doc """
  Claims the generation of a key: `:leader` generates it, `:follower` should
  `await/2` the leader. A claim older than 30 s is considered abandoned.
  """
  @spec claim(binary()) :: :leader | :follower
  def claim(key) do
    if table?() do
      inflight = {:inflight, key}

      cond do
        :ets.insert_new(@table, {inflight, now()}) ->
          :leader

        match?([{_, at}] when is_integer(at), :ets.lookup(@table, inflight)) and
            stale?(inflight) ->
          :ets.insert(@table, {inflight, now()})
          :leader

        true ->
          :follower
      end
    else
      :leader
    end
  end

  @doc "Ends a claim; the audio (if any) is kept a minute for followers."
  @spec release(binary(), binary() | nil) :: :ok
  def release(key, audio) do
    if table?() do
      if is_binary(audio) and byte_size(audio) > 0,
        do: :ets.insert(@table, {{:recent, key}, audio, now()})

      :ets.delete(@table, {:inflight, key})
    end

    :ok
  end

  @doc "Waits for the leader of a key: its audio, `:gone` if it failed, or `:timeout`."
  @spec await(binary(), non_neg_integer()) :: {:ok, binary()} | :gone | :timeout
  def await(key, timeout_ms) do
    deadline = now() + timeout_ms
    do_await(key, deadline)
  end

  defp do_await(key, deadline) do
    cond do
      match?({:ok, _}, get(key)) -> get(key)
      :ets.lookup(@table, {:inflight, key}) == [] -> :gone
      now() >= deadline -> :timeout
      true -> Process.sleep(@poll_ms) && do_await(key, deadline)
    end
  end

  defp stale?(inflight) do
    case :ets.lookup(@table, inflight) do
      [{_, at}] -> now() - at > @inflight_ms
      _ -> true
    end
  end

  defp table?, do: :ets.whereis(@table) != :undefined

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
    if evict_if_full_count() >= max_entries(), do: evict_oldest()
  end

  # Only the cache entries (binary keys) count and are evicted; the
  # in-flight and recent entries are tuples with their own lifetimes.
  defp evict_if_full_count,
    do: :ets.select_count(@table, [{{:"$1", :_, :_}, [{:is_binary, :"$1"}], [true]}])

  defp evict_oldest do
    case :ets.select(@table, [{{:"$1", :_, :"$2"}, [{:is_binary, :"$1"}], [{{:"$2", :"$1"}}]}]) do
      [] -> :ok
      entries -> :ets.delete(@table, entries |> Enum.min() |> elem(1))
    end
  end

  defp enabled?, do: max_entries() > 0 and table?()

  defp max_entries, do: Application.get_env(:agent_board, :voice_speech_cache_entries, 150)

  defp now, do: System.system_time(:millisecond)
end
