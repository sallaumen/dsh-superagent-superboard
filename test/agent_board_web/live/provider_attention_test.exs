defmodule AgentBoardWeb.ProviderAttentionTest do
  @moduledoc "A provider that cannot serve appears in the Attention bell and opens its settings."
  # The ElevenLabs account lives in one global term: this test owns it.
  use AgentBoardWeb.ConnCase, async: false

  @moduletag capture_log: true

  import Phoenix.LiveViewTest

  alias AgentBoard.Board
  alias AgentBoard.ElevenLabs.{Account, Usage}

  setup do
    Account.clear()
    on_exit(&Account.clear/0)
    :ok
  end

  test "spent ElevenLabs credits count in the bell and the item opens Costs", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "provider-bell")
    Board.log_event(repo.id, "sync", "fixture/provider-bell", %{"errors" => 0})
    :ok = Account.mark_spent()

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/provider-bell")

    assert has_element?(view, "#attention-inbox .ab-hub-menu__count", "1")
    assert has_element?(view, "#attention-elevenlabs", "Créditos da ElevenLabs esgotados")
    assert has_element?(view, "#attention-elevenlabs", "A voz do computador fala no lugar.")

    view |> element("#attention-elevenlabs button") |> render_click()
    assert_patch(view)
    assert has_element?(view, "#settings-costs-title")
    assert has_element?(view, "#costs-voice", "a voz do computador fala")
  end

  test "Costs → Voz lists each request and filters by outcome in the URL", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "voice-requests")
    Board.log_event(repo.id, "sync", "fixture/voice-requests", %{"errors" => 0})
    Usage.record_tts(321, :paid)
    Usage.record_refusal(:tts, {:error, :quota_exceeded})

    {:ok, view, _html} =
      live(conn, ~p"/?repo=fixture/voice-requests&panel=settings&section=costs&costs=voice")

    assert has_element?(view, "#costs-voice-paid", "321")
    assert has_element?(view, "#costs-voice-refused", "1")
    assert has_element?(view, "#costs-voice-requests", "321")
    assert has_element?(view, "#costs-voice-requests", "Os créditos do serviço acabaram.")

    view
    |> element("#costs-voice-filters")
    |> render_change(%{"kind" => "all", "outcome" => "refused"})

    assert_patch(
      view,
      "/?costs=voice&days=30&outcome=refused&panel=settings&repo=fixture%2Fvoice-requests&section=costs"
    )

    refute has_element?(view, "#costs-voice-requests", "321")
  end
end
