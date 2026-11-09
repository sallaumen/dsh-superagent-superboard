defmodule AgentBoardWeb.SettingsExecutionTest do
  @moduledoc "Settings → Execution: the limits draft, the empty monthly cap and the Projects link."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Settings}

  setup do
    {:ok, repo} = Board.add_repository("fixture", "execution-limits")
    :ok = Settings.put("dispatch_paused", "false")

    {:ok, repo: repo, path: "/?repo=fixture/execution-limits&panel=settings&section=execution"}
  end

  defp open(conn, path), do: live(conn, path)

  test "the Codex time and the DeepSeek link moved into their executor blocks", context do
    {:ok, view, _html} = open(context.conn, context.path)

    assert has_element?(view, "#toggle-dispatch")
    assert has_element?(view, "#executor-codex input[name=timeout_minutes]")
    refute has_element?(view, "#executor-claude_code input[name=timeout_minutes]")
    refute has_element?(view, "#execution-settings-form input[name=dsh_repositories]")

    assert has_element?(
             view,
             "#executor-dsh .ab-executor__limits-card",
             "Abrir Projetos"
           )
  end

  test "the empty monthly cap is no cap, and the draft counts and discards", context do
    {:ok, view, _html} = open(context.conn, context.path)

    view
    |> form("#execution-settings-form", %{
      "monthly_usd" => "",
      "task_usd" => "5.00",
      "timeout_minutes" => "30",
      "reserve_percent" => "20",
      "claude_model" => "claude-test",
      "codex_model" => "codex-test"
    })
    |> render_submit()

    assert Settings.get("dispatch_monthly_usd") == "0"
    assert Settings.get("dispatch_codex_timeout_minutes") == "30"
    assert Settings.get("dispatch_reserve_percent") == "20"
    assert has_element?(view, "#execution-settings-form input[name=monthly_usd][value='']")
    assert has_element?(view, ".ab-execution__dirty", "Nenhuma mudança não salva")

    view
    |> form("#execution-settings-form", %{
      "monthly_usd" => "100.00",
      "task_usd" => "5.00",
      "timeout_minutes" => "30",
      "reserve_percent" => "20",
      "claude_model" => "claude-test",
      "codex_model" => "codex-test"
    })
    |> render_change()

    assert has_element?(view, ".ab-execution__dirty", "1 mudança não salva: Teto do mês")

    view |> element("#execution-settings-form button[phx-click=discard]") |> render_click()

    assert has_element?(view, "#execution-settings-form input[name=monthly_usd][value='']")
    assert has_element?(view, ".ab-execution__dirty", "Nenhuma mudança não salva")
  end

  test "the DeepSeek card opens Projects", context do
    {:ok, view, _html} = open(context.conn, context.path)

    view
    |> element("#executor-dsh .ab-executor__limits-card button")
    |> render_click()

    assert_patch(
      view,
      "/?panel=settings&repo=fixture%2Fexecution-limits&section=projects"
    )

    assert has_element?(view, ".settings-nav__item.is-current", "Projetos")
  end
end
