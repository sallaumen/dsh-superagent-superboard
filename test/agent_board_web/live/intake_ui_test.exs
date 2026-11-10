defmodule AgentBoardWeb.IntakeUITest do
  @moduledoc "The Split form shows the spec and the tasks before anything is created."
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.Board

  @stub AgentBoardWeb.IntakeUITest.Stub

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    Application.put_env(:agent_board, :ai_api_key, "test-key")

    Application.put_env(:agent_board, :ai_client, fn ->
      Req.new(base_url: "https://api.deepseek.com", plug: {Req.Test, @stub}, retry: false)
    end)

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn ->
      Application.delete_env(:agent_board, :ai_client)
      Application.delete_env(:agent_board, :ai_api_key)
      Application.delete_env(:agent_board, :github_client)
    end)

    :ok
  end

  defp answer(content) do
    %{
      "model" => "deepseek-flash",
      "choices" => [%{"message" => %{"content" => content}}],
      "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 2}
    }
  end

  test "the ask shows the model's answer", %{conn: conn} do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    task =
      %AgentBoard.Board.Task{}
      |> AgentBoard.Board.Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 901,
        title: "Board lento",
        state: "queued"
      })
      |> AgentBoard.Repo.insert!()

    Req.Test.stub(@stub, fn conn ->
      if String.ends_with?(conn.request_path, "/chat/completions") do
        Req.Test.json(conn, answer(~s({"answer":"O sync roda a cada minuto."})))
      else
        Req.Test.json(conn, %{"id" => 1, "user" => %{"login" => "sallaumen"}})
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")
    view |> element("[data-task]") |> render_click()

    view |> element("#ask-agent") |> render_submit(%{"body" => "por que demora?"})
    render_async(view, 2_000)

    assert %AgentBoard.Board.Comment{} =
             AgentBoard.Repo.get_by!(AgentBoard.Board.Comment, task_id: task.id)

    # the model answers on another process: let it land, then render
    Process.sleep(150)
    assert render(view) =~ "O sync roda a cada minuto."
  end

  test "the panel says when the AI is not configured", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")
    Application.put_env(:agent_board, :ai_api_key, "")

    {:ok, view, html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    assert has_element?(view, "#intake-form button[disabled]")
    # The submit is the board's primary button, not a hand-coloured one.
    assert has_element?(view, "#intake-form button.ab-btn.ab-btn--primary")
    assert html =~ "não configurada"
    assert html =~ "Nenhuma chamada de IA registrada ainda."
    assert html =~ "Dividir fica indisponível"
  end

  test "failed creation reports one error and never a success", %{conn: conn} do
    {:ok, _} = Board.add_repository("fixture", "actions")

    Req.Test.stub(
      @stub,
      &Req.Test.json(Plug.Conn.put_status(&1, 422), %{"message" => "rejected"})
    )

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/actions")
    view |> element("#open-create") |> render_click()

    # The browser sends the words before the submit; the sentence that
    # confirms the creation is on screen when the person presses send.
    view |> element("#composer-form") |> render_change(%{"text" => "Fixture"})
    assert has_element?(view, "#composer-confirm", "Criar no actions a tarefa “Fixture”?")

    view
    |> element("#composer-form")
    |> render_submit(%{"text" => "Fixture"})

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
    {:ok, _} = Board.add_repository("fixture", "actions")

    Req.Test.stub(
      @stub,
      &Req.Test.json(&1, %{"number" => 123, "html_url" => "https://example.test/issues/123"})
    )

    {:ok, view, _} = live(conn, ~p"/?repo=fixture/actions")
    view |> element("#open-create") |> render_click()

    # The browser sends the words before the submit; the sentence that
    # confirms the creation is on screen when the person presses send.
    view |> element("#composer-form") |> render_change(%{"text" => "Fixture"})
    assert has_element?(view, "#composer-confirm", "Criar no actions a tarefa “Fixture”?")

    view
    |> element("#composer-form")
    |> render_submit(%{"text" => "Fixture"})

    render_async(view, 2000)

    assert has_element?(view, "#flash-info", "Pedido #123 na fila")
    assert has_element?(view, "#composer-receipt", "#123")
    refute has_element?(view, "#panel-composer .ab-compose__error")
  end

  test "the form shows the goal, the open questions and the tasks", %{conn: conn} do
    {:ok, _} = Board.add_repository("sallaumen", "arena-rogue")

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, _conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      content =
        if Enum.any?(payload["messages"], &String.contains?(&1["content"], "Specification")) do
          ~s({"tasks":[{"title":"medir o tempo","body":"mede","kind":"bug","acceptance":["p95"],"depends_on":[],"size":"S"}]})
        else
          ~s({"goal":"o board responde rapido","constraints":[],"non_goals":[],"risks":[],"blocking_questions":[],"open_questions":[],"assumptions":[],"ready":true,"language":"pt"})
        end

      Req.Test.json(conn, answer(content))
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=sallaumen/arena-rogue")

    html = view |> element("#intake-form") |> render_submit(%{"text" => "o board ta lento"})

    assert html =~ "o board responde rapido"
    assert html =~ "medir o tempo"
    assert html =~ "Últimas 2 chamadas no board."
    assert html =~ "refine_request"

    for index <- ["invalid", "-1", "99"] do
      render_hook(view, "create_from_intake", %{"index" => index})
      assert has_element?(view, "#flash-error", "Não foi possível criar a tarefa")
      assert AgentBoard.Repo.aggregate(AgentBoard.Board.Task, :count, :id) == 0
    end

    {:ok, _} = Board.add_repository("fixture", "other")
    view |> element("#repo-select") |> render_change(%{"repo" => "fixture/other"})
    refute render(view) =~ "medir o tempo"
  end

  test "an unclear request shows questions without proposing or creating tasks", %{conn: conn} do
    {:ok, _} = Board.add_repository("fixture", "unclear-intake")

    Req.Test.stub(@stub, fn conn ->
      Req.Test.json(
        conn,
        answer(
          ~s({"goal":"Melhorar o board","constraints":[],"non_goals":[],"risks":[],"blocking_questions":[],"open_questions":["Qual parte?"],"assumptions":[],"ready":false,"language":"pt"})
        )
      )
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/unclear-intake")
    view |> element("#intake-form") |> render_submit(%{"text" => "melhore o board"})

    assert has_element?(view, "#intake-needs-clarification", "precisa de mais detalhe")
    assert render(view) =~ "Qual parte?"
    refute has_element?(view, "[phx-click='create_from_intake']")
    assert AgentBoard.Repo.aggregate(AgentBoard.AI.Call, :count, :id) == 1
  end

  test "an empty proposal offers retry without claiming the request is unclear", %{conn: conn} do
    {:ok, _} = Board.add_repository("fixture", "empty-intake")

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      content =
        if Enum.any?(payload["messages"], &String.contains?(&1["content"], "Specification")) do
          ~s({"tasks":[]})
        else
          ~s({"goal":"Melhorar o board","constraints":[],"non_goals":[],"risks":[],"blocking_questions":[],"open_questions":[],"assumptions":[],"ready":true,"language":"pt"})
        end

      Req.Test.json(conn, answer(content))
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/empty-intake")
    view |> element("#intake-form") |> render_submit(%{"text" => "melhore o board"})

    assert has_element?(view, "#intake-no-tasks", "tente dividir de novo")
    refute has_element?(view, "#intake-needs-clarification")
    refute has_element?(view, "[phx-click='create_from_intake']")
  end

  test "editing or a failed new split invalidates the old proposal", %{conn: conn} do
    {:ok, _} = Board.add_repository("fixture", "stale-intake")

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      prompt = Enum.map_join(payload["messages"], " ", & &1["content"])

      cond do
        String.contains?(prompt, "pedido B") ->
          Req.Test.json(Plug.Conn.put_status(conn, 500), %{"error" => "unavailable"})

        String.contains?(prompt, "Specification") ->
          Req.Test.json(
            conn,
            answer(
              ~s({"tasks":[{"title":"Tarefa A","body":"pedido A","kind":"backend","acceptance":["teste"],"depends_on":[],"size":"S"}]})
            )
          )

        true ->
          Req.Test.json(
            conn,
            answer(
              ~s({"goal":"Fazer A","constraints":[],"non_goals":[],"risks":[],"blocking_questions":[],"open_questions":[],"assumptions":[],"ready":true,"language":"pt"})
            )
          )
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/stale-intake")
    view |> element("#intake-form") |> render_submit(%{"text" => "pedido A"})
    assert has_element?(view, "[phx-click='create_from_intake']")

    view |> element("#intake-form") |> render_change(%{"text" => "pedido B"})
    refute has_element?(view, "[phx-click='create_from_intake']")
    render_hook(view, "create_from_intake", %{"index" => "0"})
    assert has_element?(view, "#flash-error", "Não foi possível criar a tarefa")

    view |> element("#intake-form") |> render_submit(%{"text" => "pedido B"})
    refute has_element?(view, "[phx-click='create_from_intake']")
    render_hook(view, "create_from_intake", %{"index" => "0"})
    assert AgentBoard.Repo.aggregate(AgentBoard.Board.Task, :count, :id) == 0
  end
end
