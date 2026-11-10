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
  """

  import Ecto.Query

  alias AgentBoard.Repo
  alias AgentBoard.Voice.Activity

  require Logger

  @table "eleven_labs_usage"
  @default_cap 20_000

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
  Records one speech: `:paid` adds the characters ElevenLabs charged and a
  request; `:cache` is a hit served from `SpeechCache` and costs nothing.
  """
  @spec record_tts(non_neg_integer(), :paid | :cache) :: :ok
  def record_tts(characters, :paid) when is_integer(characters) and characters >= 0 do
    case add(tts_characters: characters, tts_requests: 1) do
      %{tts_characters: total} -> maybe_announce_cap(total, characters)
      _ -> :ok
    end
  end

  def record_tts(_characters, :cache) do
    add(cache_hits: 1)
    :ok
  end

  @doc "Records one transcription and its audio seconds (nil when not reported)."
  @spec record_stt(number() | nil) :: :ok
  def record_stt(seconds) do
    add(
      stt_seconds: if(is_number(seconds) and seconds > 0, do: seconds * 1.0, else: 0.0),
      stt_requests: 1
    )

    :ok
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
