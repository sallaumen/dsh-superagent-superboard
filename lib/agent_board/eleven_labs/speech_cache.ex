defmodule AgentBoard.ElevenLabs.SpeechCache do
  @moduledoc """
  Spoken audio for a text the board already paid for, in memory and in the
  database.

  The agent repeats itself on purpose (the attention calls rotate through a
  fixed pool, confirmations and errors are fixed sentences), so a repeat is
  served at once and costs nothing. The key is every input that changes the
  audio (text, voice, model, language and voice settings): changing any of
  them is a miss, never a stale voice. Only short texts (up to 300
  characters) are kept.

  Two layers. The hot one is an ETS table, bounded
  (`:voice_speech_cache_entries`, 0 disables the whole cache) with entries
  living a week, the oldest going first when it is full. The durable one is
  the `voice_speech_cache` table, so a fixed phrase is paid once, not once
  per restart: a memory miss reads it and promotes the audio back to ETS. It
  is bounded too (`:voice_speech_cache_rows`, default 1000, the least
  recently used goes first) and a row expires 30 days after its last use. A
  database failure is a miss (or a skipped write), never a failed speech.

  It also deduplicates requests in flight: WebKit opens a second request for
  the same audio while the first is still streaming, which paid ElevenLabs
  twice. The first request `claim/1`s the key; a second one `await/2`s it
  and is served the same bytes, kept briefly (`release/2`) whatever their
  length.
  """
  use GenServer

  import Ecto.Query

  alias AgentBoard.Repo

  require Logger

  @table __MODULE__
  @rows "voice_speech_cache"
  @max_text 300
  @ttl_ms 7 * 24 * 3600 * 1000
  @durable_ttl_s 30 * 24 * 3600
  # A hit refreshes its row's last use at most once a day: an expiry measured
  # in weeks does not need a write per spoken sentence.
  @touch_after_s 24 * 3600
  @default_rows 1000
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
    case memory(key) do
      {:ok, audio} -> {:ok, audio}
      :miss -> durable(key)
    end
  end

  # The two in-memory places: just produced for a follower, or cached.
  defp memory(key) do
    case recent(key) do
      {:ok, audio} -> {:ok, audio}
      :miss -> cached(key)
    end
  end

  # A memory miss reads the table; a live row goes back to ETS.
  defp durable(key) do
    if enabled?() and is_binary(key) do
      key |> read_row() |> promote(key)
    else
      :miss
    end
  end

  defp read_row(key) do
    Repo.one(
      from r in @rows,
        where: r.key == ^key and r.last_used_at > ^ago(@durable_ttl_s),
        select: %{audio: r.audio, stale?: r.last_used_at < ^ago(@touch_after_s)}
    )
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] -> db_failed(:read, e, nil)
  end

  defp promote(%{audio: audio, stale?: stale?}, key) when is_binary(audio) do
    evict_if_full()
    :ets.insert(@table, {key, audio, now()})
    if stale?, do: touch(key)
    {:ok, audio}
  end

  defp promote(_row, _key), do: :miss

  defp touch(key) do
    Repo.update_all(from(r in @rows, where: r.key == ^key),
      set: [last_used_at: DateTime.utc_now()]
    )
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] -> db_failed(:touch, e, :ok)
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
      match?({:ok, _}, memory(key)) -> memory(key)
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

  @doc "Stores the audio of a short text in both layers; a long one is not worth it."
  @spec put(binary(), String.t(), binary()) :: :ok
  def put(key, text, audio) when is_binary(audio) and byte_size(audio) > 0 do
    if enabled?() and String.length(text) <= @max_text do
      evict_if_full()
      :ets.insert(@table, {key, audio, now()})
      store(key, String.length(text), audio)
    end

    :ok
  end

  def put(_key, _text, _audio), do: :ok

  @doc "Empties the memory layer (a restart); the durable rows stay."
  def clear do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  # One upsert and one bounded prune per paid miss: the writes are as rare as
  # the misses that pay ElevenLabs.
  defp store(key, text_length, audio) when is_binary(key) do
    now = DateTime.utc_now()

    Repo.insert_all(
      @rows,
      [%{key: key, audio: audio, text_length: text_length, last_used_at: now, inserted_at: now}],
      on_conflict: {:replace, [:audio, :text_length, :last_used_at]},
      conflict_target: :key
    )

    prune()
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] -> db_failed(:write, e, :ok)
  end

  defp store(_key, _text_length, _audio), do: :ok

  defp prune do
    Repo.delete_all(from r in @rows, where: r.last_used_at <= ^ago(@durable_ttl_s))

    keep =
      from r in @rows, order_by: [desc: r.last_used_at], offset: ^max_rows(), select: r.key

    Repo.delete_all(from r in @rows, where: r.key in subquery(keep))
  end

  defp db_failed(op, error, fallback) do
    Logger.warning("speech cache #{op} skipped: #{Exception.message(error)}")
    fallback
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  defp max_rows, do: Application.get_env(:agent_board, :voice_speech_cache_rows, @default_rows)

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
