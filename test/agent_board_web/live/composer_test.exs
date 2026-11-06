defmodule AgentBoardWeb.ComposerTest do
  @moduledoc "The request layer: review the split, choose the tasks, then enqueue."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  @stub AgentBoardWeb.ComposerTest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    rehearsal = Application.get_env(:agent_board, :ai_rehearsal)
    github = Application.get_env(:agent_board, :github_client)
    Application.put_env(:agent_board, :ai_rehearsal, true)

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(
        base_url: "https://api.github.com",
        plug: {Req.Test, @stub},
        retry: false
      )
    end)

    on_exit(fn ->
      if rehearsal,
        do: Application.put_env(:agent_board, :ai_rehearsal, rehearsal),
        else: Application.delete_env(:agent_board, :ai_rehearsal)

      if github,
        do: Application.put_env(:agent_board, :github_client, github),
        else: Application.delete_env(:agent_board, :github_client)
    end)

    {:ok, repo} = Board.add_repository("fixture", "composer")
    %{repo: repo}
  end

  test "split shows the proposal before anything is enqueued", %{conn: conn} do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"number" => 9001, "html_url" => "https://github.com/x/y/issues/9001"})
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/composer")
    view |> element("#open-create") |> render_click()
    assert has_element?(view, "#board-page[data-panel=composer]")

    view |> element("#composer-form") |> render_change(%{"text" => "Quero respostas rápidas"})
    view |> element("#composer-form .ab-toggle") |> render_click()
    render_async(view, 2000)

    assert has_element?(view, "#composer-form", "Vai virar 2 tarefas")
    assert has_element?(view, "#composer-form button", "Pôr 2 na fila")
    assert Repo.aggregate(Task, :count) == 0

    view
    |> element("#composer-form")
    |> render_change(%{"text" => "Quero respostas rápidas", "tasks" => ["0"]})

    assert has_element?(view, "#composer-form button", "Pôr 1 na fila")

    view
    |> element("#composer-form")
    |> render_submit(%{"text" => "Quero respostas rápidas", "tasks" => ["0"]})

    render_async(view, 2000)

    assert Repo.aggregate(Task, :count) == 1
    assert Repo.one(Task).title == "Medir o tempo de resposta do board"
    assert has_element?(view, "#composer-receipt", "Medir o tempo de resposta do board")
    assert has_element?(view, "#composer-receipt", "#9001")
  end

  test "a dictated request lands in the composer for review", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/composer")
    view |> element("#open-create") |> render_click()

    render_hook(view, "voice_transcript", %{"text" => "  deixe a fila menor  "})

    assert has_element?(view, "#board-page[data-panel=composer]")
    assert render(view) =~ "deixe a fila menor"
  end

  test "a single request becomes one task without the split model", %{conn: conn} do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"number" => 9002, "html_url" => "https://github.com/x/y/issues/9002"})
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/composer")
    view |> element("#open-create") |> render_click()

    view
    |> element("#composer-form")
    |> render_change(%{"text" => "Corrigir o contador\nEle está somando duas vezes."})

    view
    |> element("#composer-form")
    |> render_submit(%{"text" => "Corrigir o contador\nEle está somando duas vezes."})

    render_async(view, 2000)

    task = Repo.one(Task)
    assert task.title == "Corrigir o contador"
    assert task.body =~ "somando duas vezes"
    assert task.body =~ "@sallaumen-agent"
    assert has_element?(view, "#composer-receipt", "#9002")
  end
end
