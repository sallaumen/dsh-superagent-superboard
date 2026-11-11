defmodule AgentBoardWeb.PrRowCostTest do
  @moduledoc "A merged PR's rows show what its task cost, and nothing when no cost is attributed."
  # The costs live in one global term: this test owns it while it runs.
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{PullRequest, Task}
  alias AgentBoard.Usage.TaskCosts

  setup do
    TaskCosts.clear()
    on_exit(&TaskCosts.clear/0)
    :ok
  end

  test "the merge log and History carry the task's cost; a PR with no task shows none", %{
    conn: conn
  } do
    {:ok, repo} = Board.add_repository("fixture", "pr-cost")
    Board.log_event(repo.id, "sync", "fixture/pr-cost", %{"errors" => 0})

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 12,
      title: "Mapa",
      state: "ready"
    })
    |> Repo.insert!()

    costed = pull(repo, 3, "feat/mapa", [12])
    bare = pull(repo, 4, "chore/limpeza", [])
    ledger("feat/mapa")
    :ok = TaskCosts.refresh(tickets: [])

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/pr-cost")

    assert has_element?(view, "#sec-log .ab-pr__cost", "Claude Code")

    assert length(Regex.scan(~r/ab-pr__cost/, view |> element("#sec-log") |> render())) == 1

    {:ok, history, _html} = live(conn, ~p"/?repo=fixture/pr-cost&panel=history&list=prs")

    assert has_element?(history, "#pull-#{costed.id} .ab-pr__cost", "Claude Code")
    refute has_element?(history, "#pull-#{bare.id} .ab-pr__cost")
  end

  defp pull(repo, number, branch, closes) do
    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: number,
      title: "PR #{number}",
      state: "merged",
      merged_at: DateTime.utc_now(:second),
      closes_issues: closes,
      head_ref: branch
    })
    |> Repo.insert!()
  end

  defp ledger(branch) do
    at = DateTime.utc_now(:second)

    Repo.insert_all("usage_ledger", [
      %{
        source: "claude_code",
        execution_id: "session-1",
        day: Date.utc_today(),
        cwd: "/tmp/pr-cost",
        git_branch: branch,
        model: "claude-opus-5-5",
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
    ])
  end
end
