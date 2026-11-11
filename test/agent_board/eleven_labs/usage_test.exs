defmodule AgentBoard.ElevenLabs.UsageTest do
  @moduledoc """
  The ElevenLabs ledger: one row per day, atomic sums, cache hits that cost
  nothing, and a cap that is announced once when crossed and never stops
  anything by itself.
  """
  use AgentBoard.DataCase, async: false

  alias AgentBoard.ElevenLabs.Usage
  alias AgentBoard.Voice.Activity

  setup do
    on_exit(fn -> Application.delete_env(:agent_board, :elevenlabs_daily_char_cap) end)
    :ok
  end

  test "a day with nothing recorded is all zeros" do
    assert %{
             tts_characters: 0,
             tts_requests: 0,
             cache_hits: 0,
             stt_seconds: +0.0,
             stt_requests: 0
           } =
             Usage.today()

    assert Usage.today().day == Date.utc_today()
  end

  test "paid speech, cache hits and transcriptions add up in one row" do
    Usage.record_tts(120, :paid)
    Usage.record_tts(30, :paid)
    Usage.record_tts(0, :cache)
    Usage.record_tts(0, :cache)
    Usage.record_stt(1.5)
    Usage.record_stt(nil)

    assert %{
             tts_characters: 150,
             tts_requests: 2,
             cache_hits: 2,
             stt_seconds: 1.5,
             stt_requests: 2
           } = Usage.today()

    assert Repo.aggregate("eleven_labs_usage", :count) == 1
  end

  test "each request is one row, counts only; refusals keep their reason" do
    Usage.record_tts(120, :paid)
    Usage.record_tts(0, :cache)
    Usage.record_stt(4.5)
    assert {:error, :quota_exceeded} = Usage.record_refusal(:tts, {:error, :quota_exceeded})
    assert {:ok, :anything} = Usage.record_refusal(:tts, {:ok, :anything})
    Usage.record_refusal(:stt, {:error, {:http, 502}})

    today = Date.utc_today()
    all = Usage.requests(today, %{kind: "all", outcome: "all"})
    assert all.count == 5
    assert %DateTime{} = all.first_at

    assert [%{characters: 120, outcome: "paid"}] =
             Usage.requests(today, %{kind: "tts", outcome: "paid"}).rows

    assert ["http 502", "quota_exceeded"] =
             Usage.requests(today, %{kind: "all", outcome: "refused"}).rows
             |> Enum.map(& &1.reason)
             |> Enum.sort()

    assert [%{seconds: 4.5}] = Usage.requests(today, %{kind: "stt", outcome: "paid"}).rows
    assert Usage.requests(Date.add(today, 1), %{kind: "all", outcome: "all"}).count == 0
  end

  test "concurrent records do not lose a write" do
    1..20
    |> Enum.map(fn _ -> Task.async(fn -> Usage.record_tts(10, :paid) end) end)
    |> Enum.each(&Task.await/1)

    assert Usage.today().tts_characters == 200
  end

  test "crossing the cap records one activity event and over_cap? turns true" do
    Application.put_env(:agent_board, :elevenlabs_daily_char_cap, 100)
    Activity.subscribe()

    Usage.record_tts(60, :paid)
    refute Usage.over_cap?()
    refute_received {:voice_activity, _}

    Usage.record_tts(50, :paid)
    assert Usage.over_cap?()
    assert_received {:voice_activity, %{stage: :tts, status: :info, detail: detail}}
    assert detail =~ "daily cap reached"
    assert detail =~ "110 of 100"

    # Past the cap the speech goes on and nothing is announced again.
    Usage.record_tts(40, :paid)
    refute_received {:voice_activity, _}
    assert Usage.today().tts_characters == 150
  end

  test "a cap of 0 means none" do
    Application.put_env(:agent_board, :elevenlabs_daily_char_cap, 0)
    Usage.record_tts(1_000_000, :paid)
    refute Usage.over_cap?()
  end

  test "the default cap is 20000 characters" do
    assert Usage.cap() == 20_000
  end

  test "numbers are written with dots between thousands" do
    assert Usage.number(0) == "0"
    assert Usage.number(999) == "999"
    assert Usage.number(3420) == "3.420"
    assert Usage.number(1_234_567) == "1.234.567"
  end
end
