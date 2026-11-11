defmodule AgentBoard.ElevenLabs.Usage do
  @moduledoc """
  What the board spent on ElevenLabs, one row per UTC day (the same day as
  the AI budget): TTS characters paid, TTS requests, cache hits (which cost
  nothing) and STT audio seconds.

  `AgentBoard.ElevenLabs` records each paid answer where it arrives: the
  characters come from the `x-character-count` header, or the text length
  when the header is absent; the seconds from the transcript's
  `audio_duration_secs`. `AgentBoardWeb.VoiceController` records the cache
  hits. Every write is one atomic upsert, so concurrent requests add up.

  The daily cap (`ELEVENLABS_DAILY_CHAR_CAP`, default 20000 characters, 0
  for none) does not stop anything here: `over_cap?/0` tells the voice to
  switch to the free browser voice, and the call that crosses it records one
  voice activity event a day. A ledger failure is logged and skipped; it
  never fails the speech it was counting.

  Each request is also one row of `voice_requests` (`request/4`, read by
  `requests/2`): kind (`tts`, `stt`), outcome (`paid`, `cache`, `refused`),
  characters or seconds, and a refusal's reason. Counts only, never the text.
  Rows exist from the day the table was created; older days have only the
  daily totals.
  """

  import Ecto.Query

  alias AgentBoard.Repo
  alias AgentBoard.Voice.Activity

  require Logger

  @table "eleven_labs_usage"
  @requests "voice_requests"
  @default_cap 20_000
  @shown_requests 100

  @type day :: %{
          day: Date.t(),
          tts_characters: non_neg_integer(),
          tts_requests: non_neg_integer(),
          cache_hits: non_neg_integer(),
          stt_seconds: float(),
          stt_requests: non_neg_integer()
        }

  @doc "Today's totals; a day with nothing recorded is all zeros."
  @spec today() :: day()
  def today do
    day = Date.utc_today()

    Repo.one(
      from u in @table,
        where: u.day == ^day,
        select: %{
          day: u.day,
          tts_characters: u.tts_characters,
          tts_requests: u.tts_requests,
          cache_hits: u.cache_hits,
          stt_seconds: u.stt_seconds,
          stt_requests: u.stt_requests
        }
    ) || empty(day)
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] ->
      failed(:read, e, empty(Date.utc_today()))
  end

  @doc """
  The totals of the UTC days from `since` through today, and how many of them
  recorded anything. A failed read is nil: unknown, not zero.
  """
  @spec window(Date.t()) :: map() | nil
  def window(%Date{} = since) do
    Repo.one(
      from u in @table,
        where: u.day >= ^since,
        select: %{
          tts_characters: type(coalesce(sum(u.tts_characters), 0), :integer),
          tts_requests: type(coalesce(sum(u.tts_requests), 0), :integer),
          cache_hits: type(coalesce(sum(u.cache_hits), 0), :integer),
          stt_seconds: type(coalesce(sum(u.stt_seconds), 0.0), :float),
          stt_requests: type(coalesce(sum(u.stt_requests), 0), :integer),
          days: count(u.day)
        }
    )
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] -> failed(:read, e, nil)
  end

  @doc """
  Records one speech: `:paid` adds the characters ElevenLabs charged and a
  request; `:cache` is a hit served from `SpeechCache` and costs nothing.
  """
  @spec record_tts(non_neg_integer(), :paid | :cache) :: :ok
  def record_tts(characters, :paid) when is_integer(characters) and characters >= 0 do
    request("tts", "paid", characters: characters)

    case add(tts_characters: characters, tts_requests: 1) do
      %{tts_characters: total} -> maybe_announce_cap(total, characters)
      _ -> :ok
    end
  end

  def record_tts(_characters, :cache) do
    request("tts", "cache")
    add(cache_hits: 1)
    :ok
  end

  @doc "Records one transcription and its audio seconds (nil when not reported)."
  @spec record_stt(number() | nil) :: :ok
  def record_stt(seconds) do
    seconds = if is_number(seconds) and seconds > 0, do: seconds * 1.0, else: 0.0
    request("stt", "paid", seconds: seconds)
    add(stt_seconds: seconds, stt_requests: 1)

    :ok
  end

  @doc """
  Records a refused or failed request of `kind` (`:tts`, `:stt`) from the
  result it returned; anything but `{:error, reason}` records nothing. Answers
  the result, so it can sit in a pipeline.
  """
  @spec record_refusal(:tts | :stt, term()) :: term()
  def record_refusal(kind, {:error, reason} = result) when kind in [:tts, :stt] do
    request(Atom.to_string(kind), "refused", reason: reason_word(reason))
    result
  end

  def record_refusal(_kind, result), do: result

  defp reason_word(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_word({:http, status}), do: "http #{status}"

  defp reason_word(%{__exception__: true} = error),
    do: error.__struct__ |> inspect() |> String.slice(0, 80)

  defp reason_word(_reason), do: "error"

  @doc """
  The requests from `since` (a UTC day) that `filters` select (`kind`,
  `outcome`, `"all"` for any): the newest #{@shown_requests}, how many there
  are, and when the first row of the table was written (nil when empty). A
  failed read is nil.
  """
  @spec requests(Date.t(), map()) :: map() | nil
  def requests(%Date{} = since, filters) do
    start = DateTime.new!(since, ~T[00:00:00], "Etc/UTC")

    selected =
      from(r in @requests, where: r.inserted_at >= ^start)
      |> narrow(:kind, filters[:kind])
      |> narrow(:outcome, filters[:outcome])

    %{
      rows:
        Repo.all(
          from r in selected,
            order_by: [desc: r.inserted_at, desc: r.id],
            limit: @shown_requests,
            select: %{
              id: r.id,
              kind: r.kind,
              outcome: r.outcome,
              characters: r.characters,
              seconds: r.seconds,
              reason: r.reason,
              at: type(r.inserted_at, :utc_datetime_usec)
            }
        ),
      count: Repo.aggregate(selected, :count),
      first_at:
        Repo.one(from r in @requests, select: type(min(r.inserted_at), :utc_datetime_usec))
    }
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] -> failed(:read, e, nil)
  end

  defp narrow(query, _field, value) when value in [nil, "all"], do: query
  defp narrow(query, field, value), do: where(query, [r], field(r, ^field) == ^value)

  @doc "One row per UTC day from `since` with anything recorded, oldest first. A failed read is nil."
  @spec daily(Date.t()) :: [day()] | nil
  def daily(%Date{} = since) do
    Repo.all(
      from u in @table,
        where: u.day >= ^since,
        order_by: u.day,
        select: %{
          day: u.day,
          tts_characters: u.tts_characters,
          tts_requests: u.tts_requests,
          cache_hits: u.cache_hits,
          stt_seconds: u.stt_seconds,
          stt_requests: u.stt_requests
        }
    )
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] -> failed(:read, e, nil)
  end

  # One row per request; a failed write is logged and skipped like the totals.
  defp request(kind, outcome, fields \\ []) do
    Repo.insert_all(@requests, [
      %{
        kind: kind,
        outcome: outcome,
        characters: Keyword.get(fields, :characters, 0),
        seconds: Keyword.get(fields, :seconds, 0.0),
        reason: Keyword.get(fields, :reason),
        inserted_at: DateTime.utc_now()
      }
    ])

    :ok
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] -> failed(:write, e, :ok)
  end

  @doc "The daily character cap; 0 means none."
  @spec cap() :: non_neg_integer()
  def cap, do: Application.get_env(:agent_board, :elevenlabs_daily_char_cap, @default_cap)

  @doc "Whether today's paid characters reached the cap (never with cap 0)."
  @spec over_cap?() :: boolean()
  def over_cap? do
    cap = cap()
    cap > 0 and today().tts_characters >= cap
  end

  # One atomic upsert per record: the insert seeds the day, a conflict adds
  # to it. Returns the day's totals after the write, or nil on failure.
  defp add(increments) do
    now = DateTime.utc_now()
    row = Map.merge(empty(Date.utc_today()), Map.new(increments))

    {1, [totals]} =
      Repo.insert_all(
        @table,
        [Map.merge(row, %{inserted_at: now, updated_at: now})],
        on_conflict: [inc: increments, set: [updated_at: now]],
        conflict_target: :day,
        returning: [:tts_characters, :cache_hits, :stt_seconds]
      )

    totals
  rescue
    e in [DBConnection.ConnectionError, Postgrex.Error] -> failed(:write, e, nil)
  end

  # Only the record that takes the total across the cap announces it: the
  # upsert is atomic, so exactly one call per day sees before < cap <= after.
  defp maybe_announce_cap(total, added) do
    cap = cap()

    if cap > 0 and total >= cap and total - added < cap do
      Activity.record(
        :tts,
        :info,
        "daily cap reached: #{number(total)} of #{number(cap)} ElevenLabs characters today"
      )
    end

    :ok
  end

  defp empty(day) do
    %{
      day: day,
      tts_characters: 0,
      tts_requests: 0,
      cache_hits: 0,
      stt_seconds: 0.0,
      stt_requests: 0
    }
  end

  @doc "An integer with dots between thousands, as the board writes numbers."
  @spec number(integer()) :: String.t()
  def number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
    |> String.reverse()
  end

  defp failed(op, error, fallback) do
    Logger.warning("elevenlabs usage #{op} skipped: #{Exception.message(error)}")
    fallback
  end
end
