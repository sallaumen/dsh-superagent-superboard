defmodule AgentBoardWeb.ObjectiveTreeTest do
  @moduledoc "Como as tarefas de um objetivo se conectam, no quadro."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{Task, TaskDependency}
  alias AgentBoardWeb.BoardComponents.ObjectiveTree

  defp task(repo, number, state) do
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

  defp waits(task, blocker) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert_all(TaskDependency, [
      %{task_id: task.id, blocked_by_task_id: blocker.id, inserted_at: now, updated_at: now}
    ])
  end

  defp objective(repo, tasks, attrs \\ %{}) do
    {:ok, objective} =
      Board.create_objective(
        repo,
        Map.merge(%{title: "Jogo", done_criterion: "Tudo."}, attrs),
        Enum.map(tasks, & &1.id)
      )

    objective
  end

  describe "layout" do
    test "a task sits one column after the deepest task it waits for" do
      tasks = for id <- 1..4, do: %{id: id, number: id, title: "t", state: "queued"}
      layout = ObjectiveTree.layout(tasks, [{2, 1}, {3, 2}, {4, 1}, {4, 3}])

      assert Map.new(layout.nodes, &{&1.id, &1.column}) == %{1 => 0, 2 => 1, 3 => 2, 4 => 3}
      assert length(layout.edges) == 4
      assert layout.width > layout.height
    end

    test "tasks that wait for nothing share the first column, one under the other" do
      tasks = for id <- 1..2, do: %{id: id, number: id, title: "t", state: "queued"}
      assert [%{column: 0, y: 0}, %{column: 0, y: y}] = ObjectiveTree.layout(tasks, []).nodes
      assert y > 0
    end

    test "an edge to a task outside the group is left out" do
      tasks = [%{id: 1, number: 1, title: "t", state: "queued"}]
      assert %{edges: [], nodes: [%{column: 0}]} = ObjectiveTree.layout(tasks, [{1, 99}])
    end
  end

  test "the board draws who waits for whom and what is still open", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "arvore")
    first = task(repo, 1, "done")
    second = task(repo, 2, "queued")
    third = task(repo, 3, "queued")
    free = task(repo, 4, "running")

    waits(second, first)
    waits(third, second)

    objective(repo, [first, second, third, free], %{
      request_key: "k",
      issue_url: "https://github.com/x/y/issues/9"
    })

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/arvore")

    node = fn task -> "#objective-tree-node-#{task.id}" end

    assert has_element?(view, node.(first), "#1")
    assert has_element?(view, node.(second), "Pronta para começar")
    assert has_element?(view, node.(third), "Depende de #2, ainda aberta")
    assert has_element?(view, node.(free), "Sem dependência")
    assert has_element?(view, "a[href='https://github.com/x/y/issues/9']")

    view |> element(node.(second)) |> render_click()
    assert has_element?(view, "#board-page[data-panel=conversation]")
  end

  test "a held task says what it waits for and the owner can call the agent", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "espera")
    test_pid = self()

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(
        base_url: "https://api.github.com",
        plug: fn conn ->
          send(test_pid, {:called, conn.request_path})
          Req.Test.json(conn, %{})
        end,
        retry: false
      )
    end)

    on_exit(fn -> Application.delete_env(:agent_board, :github_client) end)

    first = task(repo, 1, "running")

    held =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 2,
        title: "Tarefa 2",
        state: "queued",
        held: true
      })
      |> Repo.insert!()

    waits(held, first)
    objective(repo, [first, held])

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/espera")

    assert has_element?(view, "#objective-tree-node-#{held.id}", "Espera #1")

    view
    |> element(".ab-tree__release button", "Chamar o agente na #2")
    |> render_click()

    assert_received {:called, "/repos/fixture/espera/issues/2/comments"}
    assert %Task{held: false} = Repo.get!(Task, held.id)
  end

  test "a group with no connections draws no tree", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "plana")
    objective(repo, [task(repo, 1, "queued"), task(repo, 2, "queued")])

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/plana")

    assert has_element?(view, "#objectives", "Jogo")
    refute has_element?(view, "[id^=objective-tree-]")
  end
end
