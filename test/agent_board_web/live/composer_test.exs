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

  # The one end-to-end check of the shipped rehearsal fixture (no key, no
  # bill): its proposal goes through the composer and lands as a task.
  test "the rehearsal split shows the proposal before anything is enqueued", %{conn: conn} do
    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(conn, %{"number" => 9001, "html_url" => "https://github.com/x/y/issues/9001"})
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/composer")
    view |> element("#open-create") |> render_click()
    assert has_element?(view, "#board-page[data-panel=composer]")

    view |> element("#composer-form") |> render_change(%{"text" => "Quero respostas rápidas"})
    view |> element("#composer-split") |> render_click()
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

  test "the board has one door; the split is one click inside it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/composer")
    refute has_element?(view, "#open-intake")

    view |> element("#open-create") |> render_click()
    # Nothing to split yet.
    assert has_element?(view, "#composer-split[disabled]")

    view |> element("#composer-form") |> render_change(%{"text" => "Quero respostas rápidas"})
    view |> element("#composer-split") |> render_click()
    render_async(view, 2000)

    assert has_element?(view, "#composer-form", "Vai virar 2 tarefas")
    assert has_element?(view, "#composer-split", "Dividir de novo")

    # Back to one request: the proposal goes and the send is a single issue.
    view |> element("#composer-unsplit") |> render_click()
    refute has_element?(view, "#composer-form", "Vai virar 2 tarefas")
    refute has_element?(view, "#composer-unsplit")
    assert has_element?(view, "#composer-form button.ab-btn--primary", "Pôr na fila")
  end

  test "the old Split link opens the composer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/composer&panel=intake")
    assert has_element?(view, "#board-page[data-panel=composer]")
  end

  test "failed creation reports one error and never a success", %{conn: conn} do
    Req.Test.stub(
      @stub,
      &Req.Test.json(Plug.Conn.put_status(&1, 422), %{"message" => "rejected"})
    )

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/composer")
    view |> element("#open-create") |> render_click()

    # The browser sends the words before the submit; the sentence that
    # confirms the creation is on screen when the person presses send.
    view |> element("#composer-form") |> render_change(%{"text" => "Fixture"})
    assert has_element?(view, "#composer-confirm", "Criar no composer a tarefa “Fixture”?")

    view |> element("#composer-form") |> render_submit(%{"text" => "Fixture"})
    render_async(view, 2000)

    assert has_element?(view, "#composer-receipt", "Nada entrou na fila: 1 falhou")

    assert has_element?(
             view,
             "#composer-receipt",
             "falhou: O GitHub respondeu com erro (HTTP 422)"
           )

    assert has_element?(view, "#composer-receipt button", "Tentar as 1 que falharam")
    refute has_element?(view, "#flash-info")
  end

  test "successful creation reports success", %{conn: conn} do
    Req.Test.stub(
      @stub,
      &Req.Test.json(&1, %{"number" => 123, "html_url" => "https://example.test/issues/123"})
    )

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/composer")
    view |> element("#open-create") |> render_click()
    view |> element("#composer-form") |> render_change(%{"text" => "Fixture"})
    view |> element("#composer-form") |> render_submit(%{"text" => "Fixture"})
    render_async(view, 2000)

    assert has_element?(view, "#flash-info", "Pedido #123 na fila")
    assert has_element?(view, "#composer-receipt", "#123")
    refute has_element?(view, "#panel-composer .ab-compose__error")
  end

  test "a dictated request lands in the composer for review", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/composer")
    view |> element("#open-create") |> render_click()

    render_hook(view, "voice_transcript", %{"text" => "  deixe a fila menor  "})

    assert has_element?(view, "#board-page[data-panel=composer]")
    assert render(view) =~ "deixe a fila menor"
  end

  test "dictating adds to what was already written", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/composer")
    view |> element("#open-create") |> render_click()
    view |> element("#composer-form") |> render_change(%{"text" => "Primeira parte"})

    render_hook(view, "voice_transcript", %{"text" => "segunda parte"})

    assert view |> element("#composer-form textarea[name=text]") |> render() =~
             "Primeira parte\nsegunda parte"
  end

  test "unchecking every proposed task leaves nothing to enqueue", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/composer")
    view |> element("#open-create") |> render_click()
    view |> element("#composer-form") |> render_change(%{"text" => "Quero respostas rápidas"})
    view |> element("#composer-split") |> render_click()
    render_async(view, 2000)

    assert has_element?(view, ~s(#composer-form input[type=hidden][name="tasks[]"]))

    view
    |> element("#composer-form")
    |> render_change(%{"text" => "Quero respostas rápidas", "tasks" => [""]})

    assert has_element?(view, "#composer-form button[disabled]", "Pôr 0 na fila")
  end
end
