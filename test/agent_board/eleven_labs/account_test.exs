defmodule AgentBoard.ElevenLabs.AccountTest do
  @moduledoc "The ElevenLabs plan as the board knows it, spent credits, and what the owner sees of it."
  # The account lives in one global term: these tests own it while they run.
  use AgentBoard.DataCase, async: false

  @moduletag capture_log: true

  alias AgentBoard.AI.Call
  alias AgentBoard.Board.Inbox
  alias AgentBoard.ElevenLabs
  alias AgentBoard.ElevenLabs.Account
  alias AgentBoardWeb.BoardComponents.Settings.Costs
  alias AgentBoardWeb.VoiceSpeech

  @stub AgentBoard.ElevenLabs.AccountTest.Stub

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    Account.clear()
    Req.Test.set_req_test_to_shared(%{})
    Application.put_env(:agent_board, :elevenlabs_api_key, "test-key")

    Application.put_env(:agent_board, :elevenlabs_client, fn ->
      Req.new(base_url: "https://api.elevenlabs.io", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn ->
      Account.clear()
      Req.Test.set_req_test_to_private(%{})
      Application.delete_env(:agent_board, :elevenlabs_client)
      Application.delete_env(:agent_board, :elevenlabs_api_key)
      Application.delete_env(:agent_board, :ai_daily_tokens)
    end)

    :ok
  end

  defp subscription(used, limit) do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{
        "tier" => "free",
        "character_count" => used,
        "character_limit" => limit,
        "next_character_count_reset_unix" => 1_796_521_373
      })
    end)
  end

  defp refuse(status) do
    Req.Test.stub(@stub, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        status,
        ~s({"detail":{"status":"quota_exceeded","message":"This request exceeds your quota."}})
      )
    end)
  end

  test "the plan is read with its use, limit and renewal, and written for Costs" do
    subscription(4_177, 10_000)
    :ok = Account.refresh(~U[2026-11-11 12:00:00Z])

    assert %{subscription: %{used: 4_177, limit: 10_000, tier: "free", resets_at: resets_at}} =
             Account.snapshot()

    assert resets_at == ~U[2026-12-06 01:42:53Z]
    refute Account.spent?(~U[2026-11-11 12:00:00Z])

    assert Costs.account(Account.snapshot(), ~U[2026-11-11 12:00:00Z], 180) ==
             "plan: 4,177 of 10,000 characters this period, renews 5 Dec"
  end

  test "a spent plan sends every utterance to the computer voice until it renews" do
    subscription(10_000, 10_000)
    :ok = Account.refresh()
    voice = %{engine: "elevenlabs", configured: true}

    assert Account.spent?(~U[2026-11-11 12:00:00Z])
    refute Account.spent?(~U[2026-12-06 02:00:00Z])
    refute VoiceSpeech.elevenlabs?(voice, :call)

    assert Costs.account(Account.snapshot(), ~U[2026-11-11 12:00:00Z], 180) ==
             "plan spent until 5 Dec: the computer voice speaks"

    assert [%{key: "elevenlabs", section: "costs"}] = Inbox.providers()
  end

  test "quota_exceeded is spent credits, not a refused key, and holds for an hour" do
    refuse(401)
    assert ElevenLabs.speech("Olá") == {:error, :quota_exceeded}
    assert Account.spent?()
    refute Account.spent?(DateTime.add(DateTime.utc_now(), 3_601, :second))

    Account.clear()
    refuse(400)
    assert ElevenLabs.speech_stream("Olá", [], fn _chunk -> :ok end) == {:error, :quota_exceeded}
    assert Account.spent?()

    # A refused key is still a refused key.
    Account.clear()

    Req.Test.stub(@stub, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(401, ~s({"detail":{"status":"invalid_api_key"}}))
    end)

    assert ElevenLabs.speech("Olá") == {:error, :auth_expired}
    refute Account.spent?()
  end

  test "the bell lists a spent AI budget and a provider whose newest call was refused" do
    assert Inbox.providers() == []

    Application.put_env(:agent_board, :ai_daily_tokens, 0)
    assert [%{key: "ai-budget", section: "execution"}] = Inbox.providers()
    Application.delete_env(:agent_board, :ai_daily_tokens)

    call(%{engine: "deepseek", status: "error", error: ":usage_limit"})
    assert [%{key: "ai-deepseek", title: title}] = Inbox.providers()
    assert title =~ "DeepSeek"

    # A later answer from the same provider clears it.
    call(%{engine: "deepseek", status: "ok"})
    assert Inbox.providers() == []
  end

  defp call(attrs) do
    %Call{}
    |> Call.changeset(Map.merge(%{name: "refine_request"}, attrs))
    |> Repo.insert!()
  end
end
