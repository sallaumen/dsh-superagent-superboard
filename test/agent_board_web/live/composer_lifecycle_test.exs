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
  alias AgentBoard.Board.{PrivateContext, Task}

  @stub AgentBoardWeb.ComposerLifecycleTest.Stub

  @refined %{
    "goal" => "o board mostra o pedido",
    "constraints" => [],
    "non_goals" => [],
    "risks" => [],
    "blocking_questions" => [],
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

  defp open_composer(conn) do
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/lifecycle")
    view |> element("#open-create") |> render_click()
    assert has_element?(view, "#board-page[data-panel=composer]")
    view
  end

  defp type(view, text) do
    view |> element("#composer-form") |> render_change(%{"text" => text})
  end

  # One click runs the whole split for the words already typed.
  defp split(view) do
    view |> element("#composer-split") |> render_click()
    render_async(view, 2000)
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

  # Typing fast: each keystroke's change carries the title field's value as
  # the browser had it, the title derived from the previous words. Only a
  # change of the title field itself (`_target`) is the owner's edit.
  test "fast typing keeps the title derived from the words", %{conn: conn} do
    github()
    view = open_composer(conn)
    form = element(view, "#composer-form")

    render_change(form, %{"_target" => ["text"], "text" => "Ve"})

    render_change(form, %{
      "_target" => ["text"],
      "text" => "Verificar o portão",
      "title" => "Ve"
    })

    render_change(form, %{
      "_target" => ["text"],
      "text" => "Verificar o portão de risco",
      "title" => "Verificar o portão"
    })

    assert has_element?(view, "#composer-issue-title[value='Verificar o portão de risco']")
    assert has_element?(view, "#composer-title-hint", "Da primeira frase")
    assert has_element?(view, "#composer-confirm", "“Verificar o portão de risco”")

    # The send may carry the field as the browser last had it; the title is
    # still the one the screen confirmed.
    submit(view, %{"text" => "Verificar o portão de risco", "title" => "Verificar o portão"})
    assert Repo.one(Task).title == "Verificar o portão de risco"
  end

  test "an edited title is the issue title", %{conn: conn} do
    github()
    view = open_composer(conn)
    type(view, "Um parágrafo bem longo que descreve o pedido inteiro em uma só linha")

    view
    |> element("#composer-form")
    |> render_change(%{
      "_target" => ["title"],
      "text" => "Um parágrafo bem longo que descreve o pedido inteiro em uma só linha",
      "title" => "Pedido curto"
    })

    assert has_element?(view, "#composer-title-hint", "Editado por você")

    # More words afterwards keep the owner's title.
    view
    |> element("#composer-form")
    |> render_change(%{
      "_target" => ["text"],
      "text" => "Um parágrafo bem longo que descreve o pedido inteiro em uma só linha, e mais",
      "title" => "Pedido curto"
    })

    assert has_element?(view, "#composer-issue-title[value='Pedido curto']")

    submit(view, %{
      "text" => "Um parágrafo bem longo que descreve o pedido inteiro em uma só linha, e mais",
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

    view = open_composer(conn)
    type(view, "O board está lento")

    view |> element("#composer-split") |> render_click()
    assert_receive {:refining, model}, 2000

    # The job is on screen while the model answers; the submit is disabled.
    assert has_element?(view, "#composer-progress", "Dividindo")
    assert has_element?(view, "#composer-form button.ab-btn--primary[disabled]")

    send(model, :answer)
    render_async(view, 2_000)

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
    # Its blocker was left out, so there is no number to name.
    refute task.body =~ "Depende de"
    assert Agent.get(counter, & &1) == 101

    # The classification is stored on the task and read back in the receipt.
    assert {task.work_type, task.size} == {"bug", "M"}
    assert has_element?(view, "#composer-receipt .ab-work", "bug")
  end

  test "split issues carry the request's context and link what they depend on", %{conn: conn} do
    github()

    script(fn
      %{name: :refine_request} ->
        Scripted.answer(%{@refined | "constraints" => ["Sem quebrar o sync"]})

      %{name: :propose_tasks} ->
        Scripted.answer(@tasks)
    end)

    view = open_composer(conn)
    type(view, "O board está lento")
    split(view)
    submit(view, %{"text" => "O board está lento", "tasks" => ["0", "1"]})

    first = Repo.get_by!(Task, title: "Medir o carregamento")
    second = Repo.get_by!(Task, title: "Corrigir o gargalo")

    assert first.number == 101
    assert first.body =~ "## Critérios de aceite\n- p95 medido"
    assert first.body =~ "**Objetivo:** o board mostra o pedido"
    assert first.body =~ "### Restrições\n- Sem quebrar o sync"
    assert String.starts_with?(second.body, "**Depende de:** #101")
    # It waits: the board calls the agent when #101 finishes.
    refute second.body =~ "@sallaumen-agent"
    assert second.held
  end

  test "the split reads the repository it is working on", %{conn: conn} do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      case conn.request_path do
        "/repos/fixture/lifecycle/git/trees/HEAD" ->
          Req.Test.json(conn, %{"tree" => [%{"path" => "lib/brand_live.ex", "type" => "blob"}]})

        _ ->
          conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})
      end
    end)

    script(fn
      %{name: :refine_request, prompt: prompt} ->
        send(test_pid, {:refine, prompt})
        Scripted.answer(@refined)

      %{name: :propose_tasks, prompt: prompt} ->
        send(test_pid, {:propose, prompt})
        Scripted.answer(@tasks)
    end)

    view = open_composer(conn)
    type(view, "O board está lento")
    split(view)

    assert_received {:refine, refine}
    assert refine =~ "lib/brand_live.ex"
    assert_received {:propose, propose}
    assert propose =~ "lib/brand_live.ex"
    assert has_element?(view, "#composer-form", "Vai virar 2 tarefas")
  end

  test "a repository that cannot be read does not stop the split", %{conn: conn} do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
    happy_model()

    view = open_composer(conn)
    type(view, "O board está lento")
    split(view)

    assert has_element?(view, "#composer-form", "Vai virar 2 tarefas")
  end

  defp github_with_files do
    test_pid = self()

    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      case {conn.method, String.contains?(conn.request_path, "/contents/")} do
        {"PUT", true} ->
          send(test_pid, :file_stored)
          conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{})

        {"POST", _} ->
          send(test_pid, {:posted, Jason.decode!(raw)})

          Req.Test.json(conn, %{
            "number" => 300,
            "html_url" => "https://github.com/fixture/lifecycle/issues/300"
          })

        _branch_exists ->
          Req.Test.json(conn, %{})
      end
    end)
  end

  test "a file attached in the composer reaches the issue", %{conn: conn} do
    github_with_files()
    view = open_composer(conn)
    type(view, "Refazer a tela de login")

    upload =
      file_input(view, "#composer-form", :attachments, [
        %{name: "login mock.png", content: "PNGDATA", type: "image/png"}
      ])

    render_upload(upload, "login mock.png")
    assert has_element?(view, "#composer-attachments", "login mock.png")

    submit(view, %{"text" => "Refazer a tela de login"})

    assert_received :file_stored
    assert_received {:posted, %{"body" => body}}
    assert body =~ "login_mock.png"
    assert body =~ "board-attachments"
  end

  test "the private context stays on this machine; the issue only gets its path", %{conn: conn} do
    github_with_files()

    source =
      Path.join(Path.expand("~"), "agent-board-composer-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(source, "screens"))
    File.write!(Path.join([source, "screens", "home.png"]), "PNG")
    on_exit(fn -> File.rm_rf!(source) end)

    view = open_composer(conn)
    type(view, "Refazer a tela de login")

    upload =
      file_input(view, "#composer-form", :attachments, [
        %{name: "antes.png", content: "OLDPNG", type: "image/png"}
      ])

    render_upload(upload, "antes.png")
    [entry] = upload.entries
    ref = entry["ref"]

    view
    |> element("#composer-form")
    |> render_change(%{
      "text" => "Refazer a tela de login",
      "private_note" => "senha do staging: hunter2",
      "attachment_meta" => %{ref => %{"private" => "true", "role" => "before"}}
    })

    # A folder outside home is refused with words; one under home is counted.
    view |> element("#composer-add-folder") |> render_click(%{"private_folder" => "/etc"})

    assert has_element?(
             view,
             "#composer-private",
             "Só dá para copiar uma pasta dentro da sua home"
           )

    view |> element("#composer-add-folder") |> render_click(%{"private_folder" => source})
    assert has_element?(view, "#composer-private", "1 arquivo")

    submit(view, %{
      "text" => "Refazer a tela de login",
      "private_note" => "senha do staging: hunter2"
    })

    # Nothing private went to GitHub: no file stored, no secret in the issue.
    refute_received :file_stored
    assert_received {:posted, %{"body" => body}}
    refute body =~ "hunter2"
    refute body =~ "board-attachments"

    repo = Board.repository_by_slug("fixture/lifecycle")
    dir = PrivateContext.request_dir(repo, "Refazer a tela de login")
    path = PrivateContext.path(repo, dir)
    assert body =~ "## Contexto privado"
    assert body =~ path

    assert PrivateContext.read_note(repo, dir) == "senha do staging: hunter2"
    files = Enum.map(PrivateContext.list(repo, dir), & &1.path)
    assert "files/before--antes.png" in files
    assert "files/#{Path.basename(source)}/screens/home.png" in files
    assert has_element?(view, "#composer-receipt", "1 pedido na fila")
  end

  test "switching repository forgets the files picked under the old one", %{conn: conn} do
    {:ok, _other} = Board.add_repository("fixture", "other")
    view = open_composer(conn)
    type(view, "Pedido do primeiro")

    upload =
      file_input(view, "#composer-form", :attachments, [
        %{name: "segredo.png", content: "PNGDATA", type: "image/png"}
      ])

    render_upload(upload, "segredo.png")
    assert has_element?(view, "#composer-attachments", "segredo.png")

    render_patch(view, ~p"/?repo=fixture/other&panel=composer")

    refute has_element?(view, "#composer-attachments", "segredo.png")
    refute has_element?(view, "#composer-form textarea[name=text]", "Pedido do primeiro")
  end

  test "a file whose send failed does not follow the owner to another repository",
       %{conn: conn} do
    test_pid = self()
    {:ok, _other} = Board.add_repository("fixture", "other")

    Req.Test.stub(@stub, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      cond do
        conn.method == "PUT" and String.contains?(conn.request_path, "/fixture/lifecycle/") ->
          conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"message" => "boom"})

        conn.method == "PUT" ->
          send(test_pid, {:file_stored, conn.request_path})
          conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{})

        conn.method == "POST" ->
          send(test_pid, {:posted, Jason.decode!(raw)})

          Req.Test.json(conn, %{
            "number" => 300,
            "html_url" => "https://github.com/fixture/other/issues/300"
          })

        true ->
          Req.Test.json(conn, %{})
      end
    end)

    view = open_composer(conn)
    type(view, "Pedido do primeiro")

    upload =
      file_input(view, "#composer-form", :attachments, [
        %{name: "segredo.png", content: "PNGDATA", type: "image/png"}
      ])

    render_upload(upload, "segredo.png")
    submit(view, %{"text" => "Pedido do primeiro"})
    refute_received {:posted, _}

    render_patch(view, ~p"/?repo=fixture/other&panel=composer")
    type(view, "Pedido do outro")
    submit(view, %{"text" => "Pedido do outro"})

    refute_received {:file_stored, _}
    assert_received {:posted, %{"body" => body}}
    refute body =~ "segredo"
  end

  test "a type the board does not take is refused where it was chosen", %{conn: conn} do
    github_with_files()
    view = open_composer(conn)
    type(view, "Refazer a tela de login")

    upload =
      file_input(view, "#composer-form", :attachments, [
        %{name: "run.exe", content: "MZ", type: "application/octet-stream"}
      ])

    assert {:error, [[_ref, :not_accepted]]} = render_upload(upload, "run.exe")
    assert has_element?(view, "#composer-attachments", "Tipo não aceito")
    assert has_element?(view, "#composer-form button.ab-btn--primary[disabled]")
  end

  test "two tasks with the same title open two issues and keep their links", %{conn: conn} do
    github()

    task = fn title, body, depends_on ->
      %{
        "title" => title,
        "body" => body,
        "kind" => "bug",
        "acceptance" => ["ok"],
        "depends_on" => depends_on,
        "size" => "S"
      }
    end

    tasks = [
      task.("Adicionar testes", "Testes do menu.", []),
      task.("Adicionar testes", "Testes da loja.", []),
      task.("Validar", "Conferir.", [1])
    ]

    script(fn
      %{name: :refine_request} -> Scripted.answer(@refined)
      %{name: :propose_tasks} -> Scripted.answer(%{"tasks" => tasks})
    end)

    view = open_composer(conn)
    type(view, "O board está lento")
    split(view)
    submit(view, %{"text" => "O board está lento", "tasks" => ["0", "1", "2"]})

    assert Repo.aggregate(Task, :count) == 3
    assert %Task{number: 102, body: loja} = Repo.get_by!(Task, number: 102)
    assert loja =~ "Testes da loja."
    assert String.starts_with?(Repo.get_by!(Task, title: "Validar").body, "**Depende de:** #102")
  end

  test "the review shows what each task says and what the AI left open", %{conn: conn} do
    github()

    script(fn
      %{name: :refine_request} ->
        Scripted.answer(%{
          @refined
          | "open_questions" => ["Qual é o alvo de p95?"],
            "assumptions" => ["Usa o Postgres atual"]
        })

      %{name: :propose_tasks} ->
        Scripted.answer(@tasks)
    end)

    view = open_composer(conn)
    type(view, "O board está lento")
    split(view)

    assert has_element?(view, "#composer-open-questions", "Qual é o alvo de p95?")
    assert has_element?(view, "#composer-understood", "Usa o Postgres atual")
    assert has_element?(view, "textarea[name='task_edits[0][body]']", "Instrumentar o load.")
    assert has_element?(view, "textarea[name='task_edits[1][acceptance]']", "p95 abaixo do alvo")
    assert has_element?(view, "#composer-task-deps-0", "Sem dependência")
    assert has_element?(view, "#composer-task-deps-1", "Depende de 1")
  end

  test "what the owner edits is what opens, and a retry does not duplicate it", %{conn: conn} do
    github(refuse: ["Corrigir de verdade"])
    happy_model()

    view = open_composer(conn)
    type(view, "O board está lento")
    split(view)

    edits = %{
      "0" => %{"title" => "Medir direito", "body" => "Medir o load todo.", "acceptance" => "x\ny"},
      "1" => %{"title" => "Corrigir de verdade", "body" => "Atacar.", "acceptance" => "z"}
    }

    params = %{"text" => "O board está lento", "tasks" => ["0", "1"], "task_edits" => edits}
    view |> element("#composer-form") |> render_change(params)
    submit(view, params)

    assert %Task{body: body} = Repo.get_by!(Task, title: "Medir direito")
    assert body =~ "Medir o load todo."
    assert body =~ "- x\n- y"

    github(start: 200)
    view |> element("button[phx-click=composer_retry]", "Tentar") |> render_click()
    render_async(view, 2000)

    assert Repo.aggregate(Task, :count) == 2
    assert %Task{number: 201, body: fixed} = Repo.get_by!(Task, title: "Corrigir de verdade")
    assert fixed =~ "#101"
  end

  test "a chosen task left empty holds the send", %{conn: conn} do
    github()
    happy_model()

    view = open_composer(conn)
    type(view, "O board está lento")
    split(view)

    edits = %{"0" => %{"title" => " ", "body" => "b", "acceptance" => "a"}}
    params = %{"text" => "O board está lento", "tasks" => ["0"], "task_edits" => edits}
    view |> element("#composer-form") |> render_change(params)

    assert has_element?(view, "#composer-incomplete")
    assert has_element?(view, "#composer-form button.ab-btn--primary[disabled]")

    view |> element("#composer-form") |> render_submit(params)
    assert Repo.aggregate(Task, :count) == 0
  end

  test "a blocker left out passes its own dependencies on", %{conn: conn} do
    github()

    three = %{
      "tasks" =>
        @tasks["tasks"] ++
          [
            %{
              "title" => "Validar",
              "body" => "Conferir.",
              "kind" => "bug",
              "acceptance" => ["ok"],
              "depends_on" => [1],
              "size" => "S"
            }
          ]
    }

    script(fn
      %{name: :refine_request} -> Scripted.answer(@refined)
      %{name: :propose_tasks} -> Scripted.answer(three)
    end)

    view = open_composer(conn)
    type(view, "O board está lento")
    split(view)

    view
    |> element("#composer-form")
    |> render_change(%{"text" => "O board está lento", "tasks" => ["0", "2"]})

    submit(view, %{"text" => "O board está lento", "tasks" => ["0", "2"]})

    assert %Task{number: 101} = Repo.get_by!(Task, title: "Medir o carregamento")
    assert String.starts_with?(Repo.get_by!(Task, title: "Validar").body, "**Depende de:** #101")
  end

  test "the composer suggests an executor, says why, and records the person's choice",
       %{conn: conn, repo: repo} do
    test_pid = self()
    previous = Application.get_env(:agent_board, :orchestrator_client)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:agent_board, :orchestrator_client, previous),
        else: Application.delete_env(:agent_board, :orchestrator_client)
    end)

    # The runner watches another repository, so it is out here.
    Application.put_env(:agent_board, :orchestrator_client, fn ->
      Req.new(base_url: "http://orchestrator.test", plug: {Req.Test, @stub}, retry: false)
    end)

    Req.Test.stub(@stub, fn
      %{host: "orchestrator.test"} = conn ->
        Req.Test.json(conn, %{
          "load" => %{"running" => 0, "queued" => 0, "maxWorkers" => 3},
          "paused" => false,
          "setup" => %{"accounts" => %{"repository" => "fixture/other"}}
        })

      conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:issue, Jason.decode!(body)})

        Req.Test.json(conn, %{
          "number" => 301,
          "html_url" => "https://github.com/fixture/lifecycle/issues/301"
        })
    end)

    view = open_composer(conn)
    render_async(view, 2_000)
    type(view, "Refazer o placar")

    assert has_element?(view, "label[for=composer-executor-claude].is-on", "sugerido")
    assert has_element?(view, "#composer-routing", "Sugestão: Claude Code.")
    assert has_element?(view, "#composer-routing", "O DeepSeek só atende o fixture/other.")
    assert has_element?(view, "#composer-routing", "Custo esperado: desconhecido")
    assert has_element?(view, "#composer-executor-note", "o DeepSeek não pega o pedido")
    assert has_element?(view, "#composer-confirm", "para o Claude Code")

    # The person picks Codex: the sentence and the note follow the choice.
    view
    |> element("#composer-form")
    |> render_change(%{"text" => "Refazer o placar", "executor" => "codex"})

    assert has_element?(view, "label[for=composer-executor-codex].is-on")
    assert has_element?(view, "#composer-confirm", "para o Codex")
    refute has_element?(view, "#composer-executor-warning")

    # Picking the runner where it does not watch is allowed, and warned.
    view
    |> element("#composer-form")
    |> render_change(%{"text" => "Refazer o placar", "executor" => "dsh"})

    assert has_element?(
             view,
             "#composer-executor-warning",
             "O DeepSeek só atende o fixture/other. A issue abre, mas não anda."
           )

    view
    |> element("#composer-form")
    |> render_change(%{"text" => "Refazer o placar", "executor" => "codex"})

    submit(view, %{"text" => "Refazer o placar", "executor" => "codex"})

    assert_received {:issue, sent}
    refute sent["body"] =~ "@sallaumen-agent"
    assert sent["labels"] == ["executor:codex"]
    assert has_element?(view, "#composer-receipt .ab-receipt__exec", "Codex")

    task = Repo.get_by!(Task, repository_id: repo.id, number: 301)
    assert task.executor == "codex"

    assert %AgentBoard.Routing.Decision{
             suggested: "claude",
             chosen: "codex",
             decided_by: "composer",
             alternatives: ["codex"]
           } = decision = Repo.get_by!(AgentBoard.Routing.Decision, task_id: task.id)

    assert "O DeepSeek só atende o fixture/other." in decision.reasons
    assert decision.signals["dsh"]["repository"] == "fixture/other"
  end

  test "without an answer from the runner the composer keeps the board's default",
       %{conn: conn} do
    github()
    view = open_composer(conn)
    render_async(view, 2_000)
    type(view, "Corrigir o contador")

    assert has_element?(view, "label[for=composer-executor-dsh].is-on", "sugerido")
    assert has_element?(view, "#composer-routing", "Não deu para ler qual repositório")
    refute has_element?(view, "#composer-executor-note")

    submit(view, %{"text" => "Corrigir o contador"})
    assert %Task{executor: "dsh", body: body} = Repo.one(Task)
    assert body =~ ~r/@sallaumen-agent\z/
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
              "blocking_questions" => [],
              "open_questions" => ["Dois testes automatizados ou duas tarefas?"]
          })
        end

      %{name: :propose_tasks} ->
        Scripted.answer(@tasks)
    end)

    view = open_composer(conn)
    type(view, "Separe em dois testes e manda ver")
    split(view)

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

    view = open_composer(conn)
    type(view, "Pedido com resposta quebrada")
    split(view)

    assert has_element?(view, "#composer-error", "fora do formato esperado")
    refute view |> element("#composer-form") |> render() =~ "malformed_output"
    assert has_element?(view, "#composer-error button", "Tentar de novo")
    assert Repo.aggregate(Task, :count) == 0

    # A checkbox or title change keeps the failure on screen; new words clear it.
    view
    |> element("#composer-form")
    |> render_change(%{
      "_target" => ["title"],
      "text" => "Pedido com resposta quebrada",
      "title" => "x"
    })

    assert has_element?(view, "#composer-error")

    happy_model()
    view |> element("#composer-error button", "Tentar de novo") |> render_click()
    render_async(view, 2000)

    refute has_element?(view, "#composer-error")
    assert has_element?(view, "#composer-form", "Vai virar 2 tarefas")
  end

  test "a model that never answers times out", %{conn: conn} do
    github()
    Application.put_env(:agent_board, :composer_timeout_ms, 200)

    # The timeout cancels the job, which kills the model's task: there is no
    # late answer to drop, and render_async returns once the task is gone.
    script(fn _request -> Process.sleep(:infinity) end)

    view = open_composer(conn)
    type(view, "Pedido que demora")
    view |> element("#composer-split") |> render_click()

    assert has_element?(view, "#composer-progress", "Dividindo")
    render_async(view, 1_000)

    assert has_element?(view, "#composer-error", "não terminou em 0 s")
    assert has_element?(view, "#composer-error button", "Tentar de novo")
    refute has_element?(view, "#composer-progress")
    refute has_element?(view, "#composer-form", "Vai virar")
  end

  test "cancelling a split drops its result and frees the form", %{conn: conn} do
    github()
    test_pid = self()

    script(fn _request ->
      send(test_pid, :splitting)
      Process.sleep(:infinity)
    end)

    view = open_composer(conn)
    type(view, "Pedido cancelado no meio")
    view |> element("#composer-split") |> render_click()
    assert_receive :splitting, 2_000
    assert has_element?(view, "#composer-progress button", "Cancelar")

    view |> element("#composer-progress button", "Cancelar") |> render_click()

    refute has_element?(view, "#composer-progress")
    refute has_element?(view, "#composer-form button.ab-btn--primary[disabled]")
    render_async(view, 1_000)
    refute has_element?(view, "#composer-form", "Vai virar")
  end

  test "a proposal survives closing and reopening the panel", %{conn: conn} do
    github()
    happy_model()
    view = open_composer(conn)
    type(view, "Pedido que fecha no meio")
    view |> element("#composer-split") |> render_click()

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

    view = open_composer(conn)
    type(view, "Pedido sem tarefas")
    split(view)

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
    view = open_composer(conn)
    type(view, "Pedido com falha parcial")
    split(view)
    submit(view, %{"text" => "Pedido com falha parcial", "tasks" => ["0", "1"]})

    assert has_element?(view, "#composer-receipt", "1 de 2 na fila; 1 falhou")

    assert has_element?(
             view,
             "#composer-receipt",
             "falhou: O GitHub respondeu com erro (HTTP 500)"
           )

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
    # The two tasks, and the issue that groups them once both exist.
    assert Agent.get(counter, & &1) == 103

    titles = Repo.all(from t in Task, select: t.title, order_by: t.id)
    assert titles == ["Medir o carregamento", "Corrigir o gargalo"]
  end

  test "a second submit while the first is in flight does nothing", %{conn: conn} do
    counter = github()
    test_pid = self()

    script(fn
      %{name: :refine_request} ->
        send(test_pid, {:refining, self()})

        receive do
          :answer -> Scripted.answer(@refined)
        end

      %{name: :propose_tasks} ->
        Scripted.answer(@tasks)
    end)

    view = open_composer(conn)
    type(view, "Clique duplo")
    view |> element("#composer-split") |> render_click()
    assert_receive {:refining, model}, 2_000

    view |> element("#composer-form") |> render_submit(%{"text" => "Clique duplo"})
    assert has_element?(view, "#composer-progress", "Dividindo")

    send(model, :answer)
    render_async(view, 2000)

    assert has_element?(view, "#composer-form", "Vai virar 2 tarefas")
    assert Agent.get(counter, & &1) == 100
    assert Repo.aggregate(AgentBoard.AI.Call, :count) == 2
  end

  test "without a configured model the split names the way out", %{conn: conn} do
    Application.put_env(:agent_board, :ai_api_key, "")
    github()
    view = open_composer(conn)
    type(view, "Sem IA")

    assert has_element?(view, "#composer-split[disabled]")

    # The single path still works.
    submit(view, %{"text" => "Sem IA"})
    assert has_element?(view, "#composer-receipt", "1 pedido na fila")
  end
end
