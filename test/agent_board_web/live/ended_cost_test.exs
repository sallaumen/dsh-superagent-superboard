defmodule AgentBoardWeb.EndedCostTest do
  @moduledoc "An ended task's row says what its executors cost, each in its own unit."
  # The costs live in one global term: this module owns it while it runs.
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{PullRequest, Task}
  alias AgentBoard.Usage.TaskCosts
  alias AgentBoardWeb.BoardNavigation

  setup do
    TaskCosts.clear()
    on_exit(&TaskCosts.clear/0)
    :ok
  end

  defp ended(repo, number, title) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: number,
      title: title,
      state: "done",
      state_changed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end

  test "a row shows each executor's cost, unknown when unpriced, and a dash with nothing", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "ended-cost")
    priced = ended(repo, 21, "Com custo")
    unpriced = ended(repo, 22, "Só Codex")
    nothing = ended(repo, 23, "Sem execução")

    for {number, branch} <- [{21, "feat/a"}, {22, "feat/b"}] do
      %PullRequest{}
      |> PullRequest.changeset(%{
        repository_id: repo.id,
        number: 100 + number,
        title: "PR",
        state: "merged",
        closes_issues: [number],
        head_ref: branch
      })
      |> Repo.insert!()
    end

    at = DateTime.utc_now() |> DateTime.truncate(:second)

    row = fn source, id, model, branch ->
      %{
        source: source,
        execution_id: id,
        day: Date.utc_today(),
        cwd: "/tmp/ended-cost",
        git_branch: branch,
        model: model,
        requests: 1,
        input_tokens: 1_000_000,
        output_tokens: 1_000_000,
        cache_read_tokens: 0,
        cache_write_tokens: 0,
        first_at: at,
        last_at: at,
        inserted_at: at,
        updated_at: at
      }
    end

    Repo.insert_all("usage_ledger", [
      row.("claude_code", "s-1", "claude-opus-5-5", "feat/a"),
      row.("codex", "t-1", "gpt-5-codex", "feat/b")
    ])

    {:ok, view, _html} = live(conn, BoardNavigation.history_path(repo))
    # before the first computation: a dash, and the tooltip says why
    assert has_element?(view, "#ended-#{priced.id} .ab-ended__cost", "—")

    assert has_element?(
             view,
             "#ended-#{priced.id} .ab-ended__cost[title*='a cada cinco minutos']"
           )

    :ok = TaskCosts.refresh(tickets: [])
    {:ok, view, _html} = live(conn, BoardNavigation.history_path(repo))

    assert has_element?(
             view,
             "#ended-#{priced.id} .ab-ended__cost",
             ~r/Claude Code ≈ US\$ [\d,.]+ lista/
           )

    assert has_element?(view, "#ended-#{unpriced.id} .ab-ended__cost", "custo desconhecido")
    assert has_element?(view, "#ended-#{nothing.id} .ab-ended__cost", "—")
    assert has_element?(view, "#ended-#{priced.id} .ab-ended__cost[title*='últimos 90 dias']")
  end
end
