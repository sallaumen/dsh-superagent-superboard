defmodule AgentBoardWeb.ObjectivesLiveTest do
  @moduledoc "O objetivo no quadro: o título, o critério e quantas tarefas já mesclaram."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  test "the board says the objective progress", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "objetivo")

    tasks =
      for number <- [1, 2] do
        %Task{}
        |> Task.changeset(%{
          repository_id: repo.id,
          kind: "issue",
          number: number,
          title: "Tarefa #{number}",
          state: "queued"
        })
        |> Repo.insert!()
      end

    {:ok, _objective} =
      Board.create_objective(
        repo,
        %{title: "Placar do jogo", done_criterion: "As duas telas mescladas."},
        Enum.map(tasks, & &1.id)
      )

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/objetivo")

    assert has_element?(view, "#objectives", "Placar do jogo")
    assert has_element?(view, "#objectives", "0 de 2 tarefas mescladas")
    assert has_element?(view, "#objectives", "As duas telas mescladas.")
  end

  test "completed objectives are a closed disclosure with their counts", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "objetivos-concluidos")

    tasks =
      for number <- [1, 2, 3, 4] do
        %Task{}
        |> Task.changeset(%{
          repository_id: repo.id,
          kind: "issue",
          number: number,
          title: "Tarefa concluída #{number}",
          state: "done"
        })
        |> Repo.insert!()
      end

    [first, second, third, fourth] = tasks

    {:ok, _} =
      Board.create_objective(
        repo,
        %{title: "Placar do jogo", done_criterion: "As duas telas mescladas."},
        [first.id, second.id]
      )

    {:ok, _} =
      Board.create_objective(
        repo,
        %{title: "Fluxo do ateliê", done_criterion: "O fluxo revisado."},
        [third.id, fourth.id]
      )

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/objetivos-concluidos")

    assert has_element?(view, "details.ab-objective-done", "2 objetivos concluídos")

    assert has_element?(
             view,
             "details.ab-objective-done .ab-objective-done__title",
             "Placar do jogo"
           )

    assert has_element?(
             view,
             "details.ab-objective-done .ab-objective-done__title",
             "Fluxo do ateliê"
           )

    assert has_element?(view, ".ab-objective-done__count", "2 de 2 ✓")
    refute has_element?(view, "details.ab-objective-done[open]")
    refute has_element?(view, "article.ab-objective")
  end
end
