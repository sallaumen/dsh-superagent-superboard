defmodule AgentBoardWeb.DailySummaryLiveTest do
  @moduledoc """
  The summary of the day on the board: it arrives with a broadcast, is
  spoken once across open boards, is dismissed everywhere, and its switch
  and hour live in Configurações.
  """
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, DailySummary, Repo}
  alias AgentBoard.DailySummary.Entry

  @path "/?repo=sallaumen/arena-rogue"

  setup do
    {:ok, _repo} = Board.add_repository("sallaumen", "arena-rogue")
    :ok
  end

  defp generate do
    # Always due: the board's own clock decides the day.
    :ok = DailySummary.put_settings(%{"at" => "00:00"})
    spend = fn _since, _until -> %{status: :none, reason: nil} end
    {:generated, entry} = DailySummary.tick(spend: spend)
    entry
  end

  defp today, do: DateTime.utc_now() |> DailySummary.local_now() |> NaiveDateTime.to_date()

  defp spoke?(view) do
    assert_push_event(view, "speak", %{text: "Resumo do dia" <> _}, 200)
    true
  rescue
    ExUnit.AssertionError -> false
  end

  test "a summary that goes out while two boards are open shows on both and is spoken once",
       %{conn: conn} do
    {:ok, one, _html} = live(conn, @path)
    {:ok, two, _html} = live(conn, @path)
    refute has_element?(one, "#daily-summary")

    generate()

    assert has_element?(one, "#daily-summary", "Resumo do dia")
    assert has_element?(two, "#daily-summary", "Resumo do dia")
    assert Enum.count([one, two], &spoke?/1) == 1

    # A board opened later shows it and stays quiet.
    {:ok, three, _html} = live(conn, @path)
    assert has_element?(three, "#daily-summary")
    refute spoke?(three)
  end

  test "a board that connects after the summary went out speaks it once", %{conn: conn} do
    generate()

    {:ok, view, _html} = live(conn, @path)
    assert has_element?(view, "#daily-summary")
    assert spoke?(view)

    {:ok, again, _html} = live(conn, @path)
    refute spoke?(again)
  end

  test "Dispensar hides it on every open board", %{conn: conn} do
    {:ok, one, _html} = live(conn, @path)
    {:ok, two, _html} = live(conn, @path)
    entry = generate()
    assert has_element?(two, "#daily-summary")

    one |> element("#daily-summary-dismiss") |> render_click()

    refute has_element?(one, "#daily-summary")
    refute has_element?(two, "#daily-summary")
    assert Repo.get!(Entry, entry.id).dismissed_at
  end

  test "renders the stored facts, each executor in its own terms", %{conn: conn} do
    Repo.insert!(%Entry{
      local_date: today(),
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      window_start: DateTime.utc_now() |> DateTime.add(-86_400) |> DateTime.truncate(:second),
      window_end: DateTime.utc_now() |> DateTime.truncate(:second),
      spoken_at: DateTime.utc_now() |> DateTime.truncate(:second),
      content: %{
        "merged" => %{
          "count" => 2,
          "items" => [
            %{
              "repo" => "sallaumen/arena-rogue",
              "number" => 12,
              "title" => "Menu",
              "url" => "u12"
            },
            %{
              "repo" => "sallaumen/arena-rogue",
              "number" => 11,
              "title" => "Mapa",
              "url" => "u11"
            }
          ]
        },
        "needs" => %{"blocked" => 1, "waiting" => 0, "items" => []},
        "sync_errors" => 0,
        "retries" => %{"sent" => 3, "tasks" => 2, "not_accepted" => 1},
        "spend" => [
          %{
            "executor" => "deepseek",
            "status" => "measured",
            "currency" => "USD",
            "micros" => 1_234_567,
            "complete" => true,
            "requests" => 40,
            "models" => ["deepseek-flash"]
          },
          %{"executor" => "claude", "status" => "unknown", "reason" => "no_source"},
          %{"executor" => "codex", "status" => "unknown", "reason" => "no_source"}
        ]
      }
    })

    {:ok, view, _html} = live(conn, @path)
    html = view |> element("#daily-summary") |> render()

    assert html =~ "2 PRs mesclados"
    assert has_element?(view, ~s(#daily-summary a[href="u12"]), "#12")
    assert html =~ "1 bloqueada"
    assert html =~ "3 novas tentativas automáticas em 2 tarefas; 1 não foi aceita"
    assert html =~ "DeepSeek <b>≈ US$ 1,23</b>"
    assert html =~ "Claude Code <b>desconhecido</b>"
    assert html =~ "Codex <b>desconhecido</b>"
    refute html =~ "Total"
  end

  test "Configurações saves the switch and the hour", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)
    assert has_element?(view, "#settings-daily-summary-section", "Todo dia às 08:00")

    view
    |> form("#daily-summary-form", %{"enabled" => "true", "at" => "09:15"})
    |> render_change()

    assert DailySummary.settings() == %{enabled: true, at: ~T[09:15:00]}
    assert has_element?(view, "#settings-daily-summary-section", "Todo dia às 09:15")

    view |> form("#daily-summary-form", %{"enabled" => "false"}) |> render_change()

    assert DailySummary.settings().enabled == false
    assert has_element?(view, "#settings-daily-summary-section", "Desligado")
    assert has_element?(view, "#daily-summary-at[disabled]")
  end

  test "a malformed hour is refused in words and nothing is saved", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    view
    |> element("#daily-summary-form")
    |> render_change(%{"enabled" => "true", "at" => "9h"})

    assert has_element?(view, "#daily-summary-form [role=alert]", "Horário inválido")
    assert DailySummary.settings().at == ~T[08:00:00]
  end

  test "a change made in another tab reaches the open settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    :ok = DailySummary.put_settings(%{"at" => "07:30"})

    assert has_element?(view, "#settings-daily-summary-section", "Todo dia às 07:30")
  end
end
