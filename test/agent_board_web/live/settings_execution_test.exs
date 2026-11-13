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

    assert has_element?(view, "#panel-settings-info", "Limites salvos.")
    refute has_element?(view, "#flash-group .board-notice")
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

  # The board writes money with a decimal comma and a pt-BR phone keypad has
  # only the comma: "2,75" is 2.75, and a partly numeric cap is refused
  # instead of being saved as its leading digits.
  # The same sentence the dispatch gate answers with: the screen never stays
  # silent about a month the board cannot price.
  test "a month with an unpriced Claude row says the total is unknown", context do
    :ok = Settings.put("dispatch_monthly_usd", "0")
    at = DateTime.utc_now() |> DateTime.truncate(:second)

    AgentBoard.Repo.insert_all("usage_ledger", [
      %{
        source: "claude_code",
        execution_id: "session-unpriced",
        day: Date.utc_today(),
        cwd: "/tmp/arena",
        model: "model-without-a-price",
        requests: 1,
        input_tokens: 0,
        output_tokens: 1_000,
        cache_read_tokens: 0,
        cache_write_tokens: 0,
        first_at: at,
        last_at: at,
        inserted_at: at,
        updated_at: at
      }
    ])

    {:ok, view, _html} = open(context.conn, context.path)

    assert has_element?(
             view,
             "#executor-claude_code .ab-executor__warning",
             "O gasto do mês tem um modelo sem preço; o teto não pode ser conferido"
           )

    refute has_element?(view, "#executor-claude_code .ab-executor__warning", "Sem teto do mês")
  end

  test "a cap with a decimal comma keeps its cents; a malformed one is refused", context do
    {:ok, view, _html} = open(context.conn, context.path)

    fields = %{
      "monthly_usd" => "120,50",
      "task_usd" => "2,75",
      "timeout_minutes" => "30",
      "reserve_percent" => "20",
      "claude_model" => "claude-test",
      "codex_model" => "codex-test"
    }

    view |> form("#execution-settings-form", fields) |> render_submit()

    assert Settings.get("dispatch_monthly_usd") == "120.50"
    assert Settings.get("dispatch_task_usd") == "2.75"

    for bad <- ["3x", "1.000,50"] do
      view
      |> form("#execution-settings-form", %{fields | "task_usd" => bad})
      |> render_submit()

      assert has_element?(view, ".ab-execution__dirty.is-error"), "#{bad} should be refused"
      assert Settings.get("dispatch_task_usd") == "2.75"
    end
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
