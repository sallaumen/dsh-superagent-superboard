defmodule AgentBoardWeb.ComposerLifecycleTest do
  @moduledoc """
  The composer lifecycle: one job at a time, a receipt read from the tasks,
  and every failure a named state with a way out. The model is scripted, so
  a malformed answer, a slow answer and open questions are deterministic.
  """
  use AgentBoardWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias AgentBoard.AI.Engines.Scripted
  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  @stub AgentBoardWeb.ComposerLifecycleTest.Stub

  @refined %{
    "goal" => "o board mostra o pedido",
    "constraints" => [],
    "non_goals" => [],
    "risks" => [],
    "open_questions" => [],
    "assumptions" => [],
    "ready" => true,
    "language" => "pt"
  }

  @tasks %{
    "tasks" => [
      %{
        "title" => "Medir o carregamento",
        "body" => "Instrumentar o load.",
        "kind" => "bug",
        "acceptance" => ["p95 medido"],
        "depends_on" => [],
        "size" => "S"
      },
      %{
        "title" => "Corrigir o gargalo",
        "body" => "Atacar a causa.",
        "kind" => "bug",
        "acceptance" => ["p95 abaixo do alvo"],
        "depends_on" => [0],
        "size" => "M"
      }
    ]
  }

  setup do
    Req.Test.set_req_test_to_shared(%{})
    on_exit(fn -> Req.Test.set_req_test_to_private(%{}) end)

    previous =
      for key <- [
            :ai_rehearsal,
            :ai_engine,
            :ai_api_key,
            :ai_script,
            :github_client,
            :composer_timeout_ms
          ],
          into: %{},
          do: {key, Application.get_env(:agent_board, key)}

    Application.put_env(:agent_board, :ai_rehearsal, false)
    Application.put_env(:agent_board, :ai_engine, Scripted)
    Application.put_env(:agent_board, :ai_api_key, "test-key")

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(base_url: "https://api.github.com", plug: {Req.Test, @stub}, retry: false)
    end)

    on_exit(fn ->
      for {key, value} <- previous do
        if is_nil(value),
          do: Application.delete_env(:agent_board, key),
          else: Application.put_env(:agent_board, key, value)
      end
    end)

    {:ok, repo} = Board.add_repository("fixture", "lifecycle")
    %{repo: repo}
  end

  defp script(fun), do: Application.put_env(:agent_board, :ai_script, fun)

  defp happy_model do
    script(fn
      %{name: :refine_request} -> Scripted.answer(@refined)
      %{name: :propose_tasks} -> Scripted.answer(@tasks)
    end)
  end

  # Issues are numbered by a counter; the stub can refuse one title.
  defp github(opts \\ []) do
    {:ok, counter} = Agent.start_link(fn -> Keyword.get(opts, :start, 100) end)
    refuse = Keyword.get(opts, :refuse, [])

    Req.Test.stub(@stub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      title = body |> Jason.decode!() |> Map.get("title")

      if title in refuse do
        Plug.Conn.send_resp(conn, 500, "boom")
      else
        number = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})

        Req.Test.json(conn, %{
          "number" => number,
          "html_url" => "https://github.com/fixture/lifecycle/issues/#{number}"
        })
      end
    end)

    counter
  end

  defp open_composer(conn, split \\ false) do
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/lifecycle")
    view |> element(if(split, do: "#open-intake", else: "#open-create")) |> render_click()
    assert has_element?(view, "#board-page[data-panel=composer]")
    view
  end

  defp type(view, text) do
    view |> element("#composer-form") |> render_change(%{"text" => text})
  end

  defp submit(view, params) do
    view |> element("#composer-form") |> render_submit(params)
    render_async(view, 2000)
  end

  test "a single request creates one task and shows a receipt with its number", %{conn: conn} do
    counter = github()
    view = open_composer(conn)
    type(view, "Corrigir o contador\nEle está somando duas vezes.")

    # The title is derived and shown before anything is sent.
    assert has_element?(view, "#composer-issue-title[value='Corrigir o contador']")

    submit(view, %{"text" => "Corrigir o contador\nEle está somando duas vezes."})

    assert has_element?(view, "#composer-receipt", "1 pedido na fila")
    assert has_element?(view, "#composer-receipt", "#101")
    assert has_element?(view, "#composer-receipt", "Corrigir o contador")

    assert has_element?(
             view,
             ~s(#composer-receipt a[href="https://github.com/fixture/lifecycle/issues/101"])
           )

    assert has_element?(view, "#flash-info", "Pedido #101 na fila")
    assert Repo.aggregate(Task, :count) == 1
    assert Agent.get(counter, & &1) == 101

    # The panel stays until the person closes it; closing a settled receipt
    # starts the next request fresh.
    assert has_element?(view, "#board-page[data-panel=composer]")
    view |> element("#composer-receipt button", "Fechar") |> render_click()
    view |> element("#open-create") |> render_click()
    refute has_element?(view, "#composer-receipt")
    assert has_element?(view, "#composer-text", "")
  end

  test "an edited title is the issue title", %{conn: conn} do
    github()
    view = open_composer(conn)
    type(view, "Um parágrafo bem longo que descreve o pedido inteiro em uma só linha")

    view
    |> element("#composer-form")
    |> render_change(%{
      "text" => "Um parágrafo bem longo que descreve o pedido inteiro em uma só linha",
      "title" => "Pedido curto"
    })

    assert has_element?(view, "#composer-title-hint", "Editado por você")

    submit(view, %{
      "text" => "Um parágrafo bem longo que descreve o pedido inteiro em uma só linha",
      "title" => "Pedido curto"
    })

    assert Repo.one(Task).title == "Pedido curto"
  end

  test "the same request twice opens one issue and says it was already queued", %{conn: conn} do
    counter = github()
    view = open_composer(conn)
    type(view, "Duas vezes o mesmo pedido")
    submit(view, %{"text" => "Duas vezes o mesmo pedido"})
    assert has_element?(view, "#composer-receipt", "#101")

    # A reload (a new LiveView) and the same words again.
    view = open_composer(conn)
    type(view, "Duas vezes o mesmo pedido")
    submit(view, %{"text" => "Duas vezes o mesmo pedido"})

    assert has_element?(view, "#composer-receipt", "já estava na fila")
    assert has_element?(view, "#composer-receipt", "#101")
    assert Repo.aggregate(Task, :count) == 1
    assert Agent.get(counter, & &1) == 101
  end

  test "a split shows progress, then the proposal, then enqueues only the chosen", %{conn: conn} do
    counter = github()
    test_pid = self()

    # The model holds its answer until the test has seen the progress: an
    # instant scripted answer could land before the first assertion.
    script(fn
      %{name: :refine_request} ->
        send(test_pid, {:refining, self()})

        receive do
          :answer -> Scripted.answer(@refined)
        end

      %{name: :propose_tasks} ->
        Scripted.answer(@tasks)
    end)

    view = open_composer(conn, true)
    type(view, "O board está lento")

    view |> element("#composer-form") |> render_submit(%{"text" => "O board está lento"})
    assert_receive {:refining, model}, 2000

    # The job is on screen while the model answers; the submit is disabled.
    assert has_element?(view, "#composer-progress", "Dividindo")
    assert has_element?(view, "#composer-form button.ab-btn--primary[disabled]")

    send(model, :answer)
    render_async(view)

    assert has_element?(view, "#composer-form", "Vai virar 2 tarefas")
    assert has_element?(view, "#composer-form button", "Pôr 2 na fila")
    # The split's kind and size, in the board's words, before anything is sent.
    assert has_element?(view, "label[for=composer-task-0] .ab-work", "bug")
    assert has_element?(view, "label[for=composer-task-0] .ab-work", "P")
    assert has_element?(view, "label[for=composer-task-1] .ab-work", "M")
    assert Repo.aggregate(Task, :count) == 0

    view
    |> element("#composer-form")
    |> render_change(%{"text" => "O board está lento", "tasks" => ["1"]})

    assert has_element?(view, "#composer-form button", "Pôr 1 na fila")

    submit(view, %{"text" => "O board está lento", "tasks" => ["1"]})

    assert has_element?(view, "#composer-receipt", "1 pedido na fila")
    assert has_element?(view, "#composer-receipt", "Corrigir o gargalo")
    assert [task] = Repo.all(Task)
    assert task.title == "Corrigir o gargalo"
    assert task.body =~ "Atacar a causa"
    assert task.body =~ "@sallaumen-agent"
    assert Agent.get(counter, & &1) == 101

    # The classification is stored on the task and read back in the receipt.
    assert {task.work_type, task.size} == {"bug", "M"}
    assert has_element?(view, "#composer-receipt .ab-work", "bug")
  end

  test "a single request has no kind and no size", %{conn: conn} do
    github()
    view = open_composer(conn)
    type(view, "Corrigir o contador")
    submit(view, %{"text" => "Corrigir o contador"})

    assert %Task{work_type: nil, size: nil} = Repo.one(Task)
    refute has_element?(view, "#composer-receipt .ab-work")
  end

  test "open questions get an answer box and the answered request is split again",
       %{conn: conn} do
    github()

    script(fn
      %{name: :refine_request, prompt: prompt} ->
        if prompt =~ "Respostas:" do
          Scripted.answer(@refined)
        else
          Scripted.answer(%{
            @refined
            | "ready" => false,
              "open_questions" => ["Dois testes automatizados ou duas tarefas?"]
          })
        end

      %{name: :propose_tasks} ->
        Scripted.answer(@tasks)
    end)

    view = open_composer(conn, true)
    type(view, "Separe em dois testes e manda ver")
    submit(view, %{"text" => "Separe em dois testes e manda ver"})

    assert has_element?(view, "#composer-form", "Dois testes automatizados ou duas tarefas?")
    assert has_element?(view, "#composer-answers")
    assert has_element?(view, "#composer-form button", "Dividir com as respostas")
    refute has_element?(view, ".ab-split__item")

    # Without an answer the split does not run again.
    submit(view, %{"text" => "Separe em dois testes e manda ver", "answers" => ""})
    assert has_element?(view, "#composer-error", "Responda as perguntas")

    submit(view, %{"text" => "Separe em dois testes e manda ver", "answers" => "Duas tarefas."})

    assert has_element?(view, "#composer-form", "Vai virar 2 tarefas")
    textarea = view |> element("#composer-text") |> render()
    assert textarea =~ "Respostas:"
    assert textarea =~ "Duas tarefas."
  end

  test "a malformed answer is a named failure with a retry, not inspect/1", %{conn: conn} do
    github()
    script(fn _request -> Scripted.malformed() end)

    view = open_composer(conn, true)
    type(view, "Pedido com resposta quebrada")
    submit(view, %{"text" => "Pedido com resposta quebrada"})

    assert has_element?(view, "#composer-error", "fora do formato esperado")
    refute view |> element("#composer-form") |> render() =~ "malformed_output"
    assert has_element?(view, "#composer-error button", "Tentar de novo")
    assert Repo.aggregate(Task, :count) == 0

    # A checkbox or title change keeps the failure on screen; new words clear it.
    view
    |> element("#composer-form")
    |> render_change(%{"text" => "Pedido com resposta quebrada", "title" => "x"})

    assert has_element?(view, "#composer-error")

    happy_model()
    view |> element("#composer-error button", "Tentar de novo") |> render_click()
    render_async(view, 2000)

    refute has_element?(view, "#composer-error")
    assert has_element?(view, "#composer-form", "Vai virar 2 tarefas")
  end

  test "a model that never answers times out, and its late answer is dropped", %{conn: conn} do
    github()
    Application.put_env(:agent_board, :composer_timeout_ms, 60)

    script(fn _request ->
      Process.sleep(400)
      Scripted.answer(@refined)
    end)

    view = open_composer(conn, true)
    type(view, "Pedido que demora")
    view |> element("#composer-form") |> render_submit(%{"text" => "Pedido que demora"})

    assert has_element?(view, "#composer-progress", "Dividindo")
    Process.sleep(120)

    assert has_element?(view, "#composer-error", "não terminou em 0 s")
    assert has_element?(view, "#composer-error button", "Tentar de novo")
    refute has_element?(view, "#composer-progress")

    Process.sleep(400)
    refute has_element?(view, "#composer-form", "Vai virar")
    assert has_element?(view, "#composer-error")
  end

  test "cancelling a split drops its result and frees the form", %{conn: conn} do
    github()

    script(fn _request ->
      Process.sleep(300)
      Scripted.answer(@refined)
    end)

    view = open_composer(conn, true)
    type(view, "Pedido cancelado no meio")
    view |> element("#composer-form") |> render_submit(%{"text" => "Pedido cancelado no meio"})
    assert has_element?(view, "#composer-progress button", "Cancelar")

    view |> element("#composer-progress button", "Cancelar") |> render_click()

    refute has_element?(view, "#composer-progress")
    refute has_element?(view, "#composer-form button.ab-btn--primary[disabled]")
    Process.sleep(350)
    refute has_element?(view, "#composer-form", "Vai virar")
  end

  test "a proposal survives closing and reopening the panel", %{conn: conn} do
    github()
    happy_model()
    view = open_composer(conn, true)
    type(view, "Pedido que fecha no meio")
    view |> element("#composer-form") |> render_submit(%{"text" => "Pedido que fecha no meio"})

    render_hook(view, "close", %{})
    assert has_element?(view, "#board-page[data-panel='']")
    render_async(view, 2000)

    view |> element("#open-create") |> render_click()
    assert has_element?(view, "#composer-form", "Vai virar 2 tarefas")
    assert has_element?(view, "#composer-text", "Pedido que fecha no meio")
  end

  test "no proposed tasks offers a retry and the single-request way out", %{conn: conn} do
    counter = github()

    script(fn
      %{name: :refine_request} -> Scripted.answer(@refined)
      %{name: :propose_tasks} -> Scripted.answer(%{"tasks" => []})
    end)

    view = open_composer(conn, true)
    type(view, "Pedido sem tarefas")
    submit(view, %{"text" => "Pedido sem tarefas"})

    assert has_element?(view, "#composer-form", "não propôs nenhuma tarefa")

    view |> element("#composer-form button", "Enviar como pedido único") |> render_click()
    render_async(view, 2000)

    assert has_element?(view, "#composer-receipt", "1 pedido na fila")
    assert Repo.one(Task).title == "Pedido sem tarefas"
    assert Agent.get(counter, & &1) == 101
  end

  test "a partial enqueue is a receipt with the failure, and the retry creates only the rest",
       %{conn: conn} do
    github(refuse: ["Corrigir o gargalo"])
    happy_model()
    view = open_composer(conn, true)
    type(view, "Pedido com falha parcial")
    submit(view, %{"text" => "Pedido com falha parcial"})
    submit(view, %{"text" => "Pedido com falha parcial", "tasks" => ["0", "1"]})

    assert has_element?(view, "#composer-receipt", "1 de 2 na fila; 1 falhou")
    assert has_element?(view, "#composer-receipt", "falhou: GitHub HTTP 500")
    assert has_element?(view, "#composer-receipt button", "Tentar as 1 que falharam")
    assert has_element?(view, "#flash-error", "Criei 1 de 2")
    assert Repo.aggregate(Task, :count) == 1

    # The failed receipt survives closing the panel.
    render_hook(view, "close", %{})
    view |> element("#open-create") |> render_click()
    assert has_element?(view, "#composer-receipt button", "Tentar as 1 que falharam")

    counter = github(start: 101)
    view |> element("#composer-receipt button", "Tentar as 1 que falharam") |> render_click()
    render_async(view, 2000)

    assert has_element?(view, "#composer-receipt", "1 pedido na fila; 1 já estava na fila")
    assert Repo.aggregate(Task, :count) == 2
    assert Agent.get(counter, & &1) == 102

    titles = Repo.all(from t in Task, select: t.title, order_by: t.id)
    assert titles == ["Medir o carregamento", "Corrigir o gargalo"]
  end

  test "a second submit while the first is in flight does nothing", %{conn: conn} do
    counter = github()

    script(fn
      %{name: :refine_request} ->
        Process.sleep(150)
        Scripted.answer(@refined)

      %{name: :propose_tasks} ->
        Scripted.answer(@tasks)
    end)

    view = open_composer(conn, true)
    type(view, "Clique duplo")
    view |> element("#composer-form") |> render_submit(%{"text" => "Clique duplo"})
    view |> element("#composer-form") |> render_submit(%{"text" => "Clique duplo"})
    render_async(view, 2000)

    assert has_element?(view, "#composer-form", "Vai virar 2 tarefas")
    assert Agent.get(counter, & &1) == 100
    assert Repo.aggregate(AgentBoard.AI.Call, :count) == 2
  end

  test "without a configured model the split names the way out", %{conn: conn} do
    Application.put_env(:agent_board, :ai_api_key, "")
    github()
    view = open_composer(conn, false)
    type(view, "Sem IA")

    assert has_element?(view, "#composer-form .ab-toggle[disabled]")

    # The single path still works.
    submit(view, %{"text" => "Sem IA"})
    assert has_element?(view, "#composer-receipt", "1 pedido na fila")
  end
end
