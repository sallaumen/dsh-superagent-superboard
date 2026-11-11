defmodule AgentBoard.ObjectivesTest do
  @moduledoc "Objetivos: um grupo de tarefas com um critério de pronto e o progresso calculado."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  setup do
    {:ok, repo} = Board.add_repository("fixture", "objectives")
    %{repo: repo}
  end

  defp task!(repo, number, state \\ "queued") do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: number,
      title: "Tarefa #{number}",
      state: state
    })
    |> Repo.insert!()
  end

  test "a group has a done criterion and progress from the tasks", %{repo: repo} do
    one = task!(repo, 1)
    two = task!(repo, 2)

    assert {:ok, objective} =
             Board.create_objective(
               repo,
               %{title: "Placar", done_criterion: "As duas telas mescladas."},
               [one.id, two.id]
             )

    assert [%{id: id, merged: 0, total: 2, done?: false}] = Board.objectives(repo)
    assert id == objective.id

    one |> Task.changeset(%{state: "done"}) |> Repo.update!()

    assert [%{merged: 1, total: 2, done?: false}] = Board.objectives(repo)
  end

  test "a second split with the same request key reuses the objective", %{repo: repo} do
    one = task!(repo, 1)
    two = task!(repo, 2)
    three = task!(repo, 3)
    attrs = %{title: "Placar", done_criterion: "Pronto.", request_key: "split-1"}

    assert {:ok, first} = Board.create_objective(repo, attrs, [one.id, two.id])
    assert {:ok, again} = Board.create_objective(repo, attrs, [two.id, three.id])

    assert again.id == first.id
    assert [%{id: id, total: 3}] = Board.objectives(repo)
    assert id == first.id
  end

  test "one task is not a group", %{repo: repo} do
    one = task!(repo, 1)

    assert {:error, :not_a_group} =
             Board.create_objective(repo, %{title: "Um", done_criterion: "Pronto."}, [one.id])
  end
end
