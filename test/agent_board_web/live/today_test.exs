defmodule AgentBoardWeb.TodayTest do
  @moduledoc "A visão Hoje no board: os dois repositórios numa lista só, o gasto do dia e o clique que troca de repositório."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task
  alias AgentBoardWeb.BoardComponents.Today

  @path "/?view=hoje"

  setup do
    {:ok, arena} = Board.add_repository("fixture", "arena")
    {:ok, colmex} = Board.add_repository("fixture", "colmex")

    blocked = task(arena, 1, "blocked", "Fila do arena")
    ready = task(colmex, 2, "ready", "Revisar o colmex")

    ledger("claude_code", "session-1", "claude-opus-5-5")
    ledger("dsh", "ticket-1", "deepseek-flash")

    Repo.insert_all("usage_limits", [
      %{
        source: "codex",
        limit_id: "codex",
        plan_type: "chatgpt",
        primary_used_percent: 90.0,
        primary_window_minutes: 10_080,
        observed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    ])

    %{arena: arena, colmex: colmex, blocked: blocked, ready: ready}
  end

  defp task(repo, number, state, title) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: number,
      title: title,
      state: state
    })
    |> Repo.insert!()
  end

  defp ledger(source, execution, model) do
    at = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all("usage_ledger", [
      %{
        source: source,
        execution_id: execution,
        day: Date.utc_today(),
        cwd: "/tmp/arena",
        git_branch: nil,
        model: model,
        requests: 2,
        input_tokens: 1_000_000,
        output_tokens: 1_000_000,
        cache_read_tokens: 0,
        cache_write_tokens: 0,
        first_at: at,
        last_at: at,
        inserted_at: at,
        updated_at: at
      }
    ])

    Repo.insert_all("usage_messages", [
      %{
        source: source,
        message_id: "message-" <> execution,
        execution_id: execution,
        at: at,
        day: Date.utc_today(),
        cwd: "/tmp/arena",
        git_branch: nil,
        model: model,
        input_tokens: 1_000_000,
        output_tokens: 1_000_000,
        cache_read_tokens: 0,
        cache_write_tokens: 0
      }
    ])
  end

  test "the Hoje date is the owner's day, west of UTC" do
    now = ~U[2026-11-08 00:30:00Z]

    html =
      render_component(&Today.today_view/1, %{
        today: %{needs: [], running: []},
        spend: nil,
        offset: 180,
        now: now
      })

    assert html =~ "sábado 7 de novembro"
    refute html =~ "domingo 8 de novembro"
  end

  test "o que precisa do dono aparece numa lista só, com o repositório em cada item",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    needs = view |> element("#today-needs") |> render()

    assert needs =~ "fixture/arena"
    assert needs =~ "fixture/colmex"
    assert needs =~ "#1"
    assert needs =~ "#2"
    assert needs =~ "Fila do arena"
    assert needs =~ "Revisar o colmex"
  end

  test "o gasto do dia mostra as três moedas, sem somar", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    spend = view |> element("#today-spend") |> render()

    assert spend =~ "DeepSeek"
    assert spend =~ "≈ US$"
    assert spend =~ "Claude Code"
    assert spend =~ "≈ US$"
    assert spend =~ "Codex"
    assert spend =~ "90% da cota semanal"
    refute spend =~ "Total"
  end

  test "clicar num item de outro repositório abre a tarefa nele", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    assert has_element?(view, "#today-needs", "Revisar o colmex")

    view |> element("#today-needs button", "Revisar o colmex") |> render_click()

    assert has_element?(view, "#conversation-title", "Revisar o colmex")
    assert render(view) =~ "fixture/colmex"
  end

  test "um broadcast de outro repositório atualiza o Hoje aberto", %{
    conn: conn,
    colmex: colmex
  } do
    {:ok, view, _html} = live(conn, @path)

    refute has_element?(view, "#today-needs", "Nova do colmex")

    %Task{}
    |> Task.changeset(%{
      repository_id: colmex.id,
      kind: "issue",
      number: 9,
      title: "Nova do colmex",
      state: "blocked"
    })
    |> Repo.insert!()

    Board.broadcast(colmex.id)

    assert has_element?(view, "#today-needs", "Nova do colmex")
  end
end
