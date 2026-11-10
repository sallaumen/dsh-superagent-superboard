defmodule AgentBoard.Board.EndedTest do
  use AgentBoard.DataCase, async: true

  alias AgentBoard.Board
  alias AgentBoard.Board.{PullRequest, Task}

  @now ~U[2026-11-10 12:00:00Z]

  setup do
    {:ok, repo} = Board.add_repository("fixture", "ended-page")
    %{repo: repo}
  end

  test "ended tasks come newest first, each with how it ended", %{repo: repo} do
    task(repo, 1, "Merged work", "done", 10)
    task(repo, 2, "Closed by hand", "done", 20)
    task(repo, 3, "Stopped work", "stopped", 30, %{stopped: true})
    task(repo, 4, "Archived work", "archived", 40, %{archived: true})
    task(repo, 5, "Still queued", "queued", 1)
    task(repo, 6, "No instant recorded", "done", nil)

    pull(repo, 41, "merged", [1])
    # An open PR that names the issue does not make it merged.
    pull(repo, 42, "open", [2])

    page = Board.ended_page(repo.id)

    assert Enum.map(page, & &1.number) == [1, 2, 3, 4, 6]
    assert Enum.map(page, & &1.outcome) == [:merged, :closed, :stopped, :archived, :closed]
    assert hd(page).pull == %{number: 41, url: nil}
    assert List.last(page).ended_at == nil
  end

  test "a merged pull request wins over another that names the same issue", %{repo: repo} do
    task(repo, 1, "Two attempts", "done", 10)
    pull(repo, 41, "merged", [1])
    pull(repo, 42, "closed", [1])

    assert [%{outcome: :merged, pull: %{number: 41}}] = Board.ended_page(repo.id)
  end

  test "the search takes a number or a piece of the title", %{repo: repo} do
    task(repo, 12, "Salvar replays", "done", 10)
    task(repo, 120, "Outro assunto", "done", 20)
    task(repo, 7, "100% de cobertura", "done", 30)

    assert [%{number: 12}] = Board.ended_page(repo.id, "#12")
    assert [%{number: 12}] = Board.ended_page(repo.id, " 12 ")
    assert [%{number: 12}] = Board.ended_page(repo.id, "REPLAY")
    assert [%{number: 7}] = Board.ended_page(repo.id, "100%")
    # A wildcard in the words is a character, not a pattern.
    assert Board.ended_page(repo.id, "%") == [
             Enum.find(Board.ended_page(repo.id), &(&1.number == 7))
           ]

    assert Board.ended_page(repo.id, "nothing like this") == []
  end

  test "a cursor continues the page without repeating a row", %{repo: repo} do
    for n <- 1..5, do: task(repo, n, "Task #{n}", "done", n)

    first = Board.ended_page(repo.id, nil, nil, 2)
    last = List.last(first)
    rest = Board.ended_page(repo.id, nil, {last.ended_at, last.id}, 10)

    assert Enum.map(first, & &1.number) == [1, 2]
    assert Enum.map(rest, & &1.number) == [3, 4, 5]
  end

  defp task(repo, number, title, state, minutes_ago, extra \\ %{}) do
    at = minutes_ago && DateTime.add(@now, -minutes_ago, :minute)

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: number,
      title: title,
      state: state
    })
    |> Ecto.Changeset.change(Map.merge(%{state_changed_at: at}, extra))
    |> Repo.insert!()
  end

  defp pull(repo, number, state, closes) do
    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: number,
      title: "PR #{number}",
      state: state
    })
    |> Ecto.Changeset.change(closes_issues: closes)
    |> Repo.insert!()
  end
end
