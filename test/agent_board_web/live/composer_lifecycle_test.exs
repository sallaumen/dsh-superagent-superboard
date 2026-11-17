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
        "project_guide" => "",
        "review_method" => "performance",
        "verification" => "Comparar o p95 com a mesma carga antes e depois.",
        "depends_on" => [],
        "size" => "S"
      },
      %{
        "title" => "Corrigir o gargalo",
        "body" => "Atacar a causa.",
        "kind" => "bug",
        "acceptance" => ["p95 abaixo do alvo"],
        "project_guide" => "",
        "review_method" => "performance",
        "verification" => "Comparar o p95 com a mesma carga antes e depois.",
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

    Req.Test.stub(@stub, fn
      %{method: "GET", request_path: "/repos/fixture/lifecycle/git/trees/HEAD"} = conn ->
        Req.Test.json(conn, %{
          "tree" => for(path <- opts[:paths] || [], do: %{"path" => path, "type" => "blob"})
        })

      %{method: "GET"} = conn ->
        Req.Test.json(conn, [])

      conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        issue = Jason.decode!(body)
        title = issue["title"]
        if recipient = opts[:capture], do: send(recipient, {:github_issue, title, issue["body"]})

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

  test "a paused DeepSeek receipt opens maintenance for its project without resuming it", %{
    conn: conn,
    repo: repo
  } do
    github()

    {:ok, agent} =
      AgentBoard.Superagents.create(%{
        repository_id: repo.id,
        profile: "superagent-lifecycle",
        state_dir: "/tmp/superagent-lifecycle",
        port: 3135
      })

    {:ok, _} = AgentBoard.Superagents.observe(agent, %{state: "paused"})
    view = open_composer(conn)
    request = "Ajustar a mira"
    type(view, request)
    submit(view, %{"text" => request, "executor" => "dsh"})
    link = element(view, "#composer-paused-agent a")
    assert has_element?(view, "#composer-receipt", "#101")
    render_click(link)

    assert has_element?(
             view,
             "#project-#{agent.id}-view-maintenance button[phx-value-action=resume]"
           )

    assert AgentBoard.Superagents.get(agent.id).observed_state == "paused"
  end

  test "a pause in another project, a different executor or a finished issue does not explain this receipt" do
    repo = %{id: 5, owner: "fixture", name: "game"}
    agent = %{repository_id: 5, observed_state: "paused"}
    task = %{repository_id: 5, executor: "dsh", state: "queued"}

    for {agents, item} <- [
          {[%{agent | repository_id: 6}], task},
          {[%{agent | observed_state: "ready"}], task},
          {[agent], %{task | executor: "codex"}},
          {[agent], %{task | state: "merged"}}
        ] do
      refute AgentBoardWeb.ComposerLifecycle.paused_agent_path(repo, agents, %{
               items: [%{outcome: :existing, task: item}]
             })
    end
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
    refute has_element?(view, "#composer-submit:not([disabled])")

    send(model, :answer)
    render_async(view, 2_000)

    assert has_element?(view, "#composer-form", "2 tarefas prontas para revisão")
    assert has_element?(view, "#composer-form button", "Publicar 2 tarefas no GitHub")
    # The split's kind and size, in the board's words, before anything is sent.
    assert has_element?(view, "label[for=composer-task-0] .ab-work", "bug")
    assert has_element?(view, "label[for=composer-task-0] .ab-work", "P")
    assert has_element?(view, "label[for=composer-task-1] .ab-work", "M")
    assert Repo.aggregate(Task, :count) == 0

    view
    |> element("#composer-form")
    |> render_change(%{"text" => "O board está lento", "tasks" => ["1"]})

    assert has_element?(view, "#composer-form button", "Publicar 1 tarefa no GitHub")

    submit(view, %{"text" => "O board está lento", "tasks" => ["1"]})

    assert has_element?(view, "#composer-receipt", "1 pedido na fila")
    assert has_element?(view, "#composer-receipt", "Corrigir o gargalo")
    assert [task] = Repo.all(Task)
    assert task.title == "Corrigir o gargalo"
    assert task.body =~ "Atacar a causa"
    assert task.body =~ "@example-bot"
    # Its blocker was left out, so there is no number to name.
    refute task.body =~ "Depende de"
    assert Agent.get(counter, & &1) == 101

    # The classification is stored on the task and read back in the receipt.
    assert {task.work_type, task.size} == {"bug", "M"}
    assert has_element?(view, "#composer-receipt .ab-work", "bug")
  end

  test "a split ceiling reaches the AI and an oversized answer stays reviewable without publishing",
       %{conn: conn} do
    owner = self()
    counter = github()

    script(fn
      %{name: :refine_request} ->
        Scripted.answer(@refined)

      %{name: :propose_tasks, prompt: prompt} ->
        send(owner, {:prompt, prompt})
        Scripted.answer(@tasks)
    end)

    view = open_composer(conn)
    words = "Medir e corrigir o contador"
    type(view, words)
    view |> element("#composer-form") |> render_change(%{"max_tasks" => "1"})
    split(view)
    assert_receive {:prompt, prompt}
    assert prompt =~ "Maximum tasks: 1."
    assert has_element?(view, "#composer-split-limit-note")

    for n <- 0..1 do
      assert has_element?(view, "#composer-task-#{n}")
      refute has_element?(view, "#composer-task-#{n}[checked]")
    end

    refute has_element?(view, "#composer-confirm")
    assert has_element?(view, "#composer-form button[type=submit][disabled]")

    # A stale/forged submit cannot relax the ceiling or enqueue both tasks.
    for limit <- ["", "1", "999"] do
      submit(view, %{"text" => words, "max_tasks" => limit, "tasks" => ["0", "1"]})
      assert Repo.aggregate(Task, :count) == 0
      assert Agent.get(counter, & &1) == 100
    end

    view |> element("#composer-form") |> render_change(%{"tasks" => ["1"], "max_tasks" => "1"})
    submit(view, %{"text" => words, "tasks" => ["1"], "max_tasks" => "1"})
    assert [task] = Repo.all(Task)
    assert task.title == "Corrigir o gargalo"
    assert Agent.get(counter, & &1) == 101
  end

  test "editing a draft during an AI split cannot restore stale tasks", %{conn: conn} do
    owner = self()

    script(fn
      %{name: :refine_request} ->
        Scripted.answer(@refined)

      %{name: :propose_tasks} ->
        send(owner, {:proposing, self()})

        receive do
          :answer -> Scripted.answer(@tasks)
        end
    end)

    view = open_composer(conn)
    type(view, "Pedido original")
    view |> element("#composer-split") |> render_click()
    assert_receive {:proposing, worker}
    form = element(view, "#composer-form")
    render_change(form, %{"text" => "Pedido corrigido", "max_tasks" => "3"})
    send(worker, :answer)
    render_async(view, 2000)
    assert has_element?(view, "#composer-text", "Pedido corrigido")
    refute has_element?(view, "#composer-task-0")
    assert has_element?(view, "#composer-max-tasks option[value='3'][selected]")
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
    refute second.body =~ "@example-bot"
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
    assert has_element?(view, "#composer-form", "2 tarefas prontas para revisão")
  end

  test "a repository that cannot be read does not stop the split", %{conn: conn} do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
    happy_model()

    view = open_composer(conn)
    type(view, "O board está lento")
    split(view)

    assert has_element?(view, "#composer-form", "2 tarefas prontas para revisão")
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

  test "removing a file or a folder, sending as one request and starting over", %{conn: conn} do
    github()

    source =
      Path.join(Path.expand("~"), "agent-board-remove-#{System.unique_integer([:positive])}")

    File.mkdir_p!(source)
    File.write!(Path.join(source, "a.png"), "PNG")
    on_exit(fn -> File.rm_rf!(source) end)

    view = open_composer(conn)
    type(view, "Trocar o logo")

    # A picked file goes away from the list.
    upload =
      file_input(view, "#composer-form", :attachments, [
        %{name: "logo.png", content: "PNG", type: "image/png"}
      ])

    render_upload(upload, "logo.png")
    [entry] = upload.entries
    view |> element(~s(button[phx-value-ref="#{entry["ref"]}"])) |> render_click()
    refute has_element?(view, "#composer-attachments", "logo.png")

    # A named folder goes away too.
    view |> element("#composer-add-folder") |> render_click(%{"private_folder" => source})
    assert has_element?(view, "#composer-private", Path.basename(source))
    view |> element(~s(button[phx-value-path="#{source}"])) |> render_click()
    refute has_element?(view, "#composer-private", Path.basename(source) <> "/")

    # Sent as one request, then a new one starts empty.
    submit(view, %{"text" => "Trocar o logo"})
    assert has_element?(view, "#composer-receipt", "1 pedido na fila")

    view |> element("#composer-receipt button", "Novo pedido") |> render_click()
    refute has_element?(view, "#composer-receipt")
    refute view |> element("#composer-text") |> render() =~ "Trocar o logo"
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
    [dir] = File.ls!(Path.join([PrivateContext.root(), "fixture", "lifecycle"]))
    path = PrivateContext.shared_path(repo, dir)
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
        "project_guide" => "",
        "review_method" => "performance",
        "verification" => "Comparar o p95 com a mesma carga antes e depois.",
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

  test "reviewed shared context reaches each GitHub issue and the objective", %{conn: conn} do
    github(capture: self())
    wrong = "Mesma branch e um único PR."
    assumption = "O executor é sempre o mesmo."
    corrected = "Uma branch e um PR por tarefa."
    request = "Melhorar o tempo de resposta"

    script(fn
      %{name: :refine_request} ->
        Scripted.answer(%{
          @refined
          | "constraints" => [wrong, "Manter os checks locais."],
            "assumptions" => [assumption],
            "open_questions" => ["Qual a meta de latência?"]
        })

      %{name: :propose_tasks} ->
        Scripted.answer(@tasks)
    end)

    view = open_composer(conn)
    type(view, request)
    split(view)

    assert has_element?(view, "textarea#composer-shared-constraints", wrong)
    assert has_element?(view, "textarea#composer-shared-assumptions", assumption)

    form(view, "#composer-form", %{"shared_context" => %{"assumptions" => ""}}) |> render_change()
    refute has_element?(view, "#composer-shared-assumptions", assumption)

    # The final constraint edit is submitted directly, without a preceding change event.
    form(view, "#composer-form", %{
      "shared_context" => %{"constraints" => "Manter os checks locais.\n#{corrected}"}
    })
    |> render_submit()

    render_async(view, 2000)

    for title <- ["Medir o carregamento", "Corrigir o gargalo", request] do
      assert_received {:github_issue, ^title, body}
      assert body =~ corrected
      assert body =~ "Manter os checks locais."
      assert body =~ "Qual a meta de latência?"
      refute body =~ wrong
      refute body =~ assumption
    end

    objective = Repo.get_by!(AgentBoard.Board.Objective, title: request)
    assert objective.spec["constraints"] == ["Manter os checks locais.", corrected]
    assert objective.spec["assumptions"] == []
  end

  test "answers from final submit go to children and objective as decisions, blank questions stay open",
       %{conn: conn} do
    github(capture: self())
    questions = ["Qual o teto?", "A fase?", "Qual o custo?"]

    script(fn
      %{name: :refine_request} -> Scripted.answer(%{@refined | "open_questions" => questions})
      %{name: :propose_tasks} -> Scripted.answer(@tasks)
    end)

    view = open_composer(conn)
    request = "Variar o enxame"
    type(view, request)
    split(view)
    [cap, phase, cost] = Enum.map(questions, &AgentBoard.Intake.question_key/1)

    form(view, "#composer-form", %{
      "shared_context" => %{"answers" => %{cap => "três", phase => "segunda"}}
    })
    |> render_change()

    form(view, "#composer-form", %{
      "shared_context" => %{"answers" => %{cap => "oito", phase => " ", cost => ""}}
    })
    |> render_submit()

    render_async(view, 2000)

    for title <- ["Medir o carregamento", "Corrigir o gargalo", request] do
      assert_received {:github_issue, ^title, body}
      assert body =~ "### Decisões\n- Qual o teto? — oito"
      assert body =~ "### Perguntas em aberto\n- A fase?\n- Qual o custo?"
      refute body =~ "três"
      refute body =~ "segunda"
    end

    objective = Repo.get_by!(AgentBoard.Board.Objective, title: request)
    assert objective.spec["open_questions"] == ["A fase?", "Qual o custo?"]
    assert objective.spec["decisions"] == ["Qual o teto? — oito"]
    refute Map.has_key?(objective.spec, "answers")
  end

  test "reviewing one child's proof doesn't change its sibling or publish an invented guide", %{
    conn: conn
  } do
    guide = ".agents/skills/swarm-art/SKILL.md"
    github(capture: self(), paths: [guide])
    [first, second] = @tasks["tasks"]

    first = %{
      first
      | "review_method" => "motion",
        "project_guide" => guide,
        "verification" => "Compare seed 7"
    }

    second = %{second | "project_guide" => ".agents/skills/imaginary/SKILL.md"}

    script(fn
      %{name: :refine_request} ->
        Scripted.answer(@refined)

      %{name: :propose_tasks, prompt: prompt} ->
        true =
          String.contains?(prompt, guide) and
            String.contains?(prompt, "Original request:\nRevisar o impacto")

        Scripted.answer(%{"tasks" => [first, second]})
    end)

    view = open_composer(conn)
    type(view, "Revisar o impacto")
    split(view)
    assert has_element?(view, "#composer-proof-0", "Compare seed 7")
    assert has_element?(view, ~s(input[value="#{guide}"][checked]))

    edits = %{
      "0" => %{
        "title" => first["title"],
        "body" => first["body"],
        "acceptance" => "Só o alvo cede",
        "verification" => "Repetir a cena sem números",
        "guides" => [guide, "forged"]
      }
    }

    submit(view, %{"text" => "Revisar o impacto", "task_edits" => edits, "tasks" => ["0", "1"]})
    assert_received {:github_issue, "Medir o carregamento", one}
    assert one =~ "## Como verificar\nRepetir a cena sem números"
    assert one =~ "https://github.com/fixture/lifecycle/blob/HEAD/#{guide}"
    refute one =~ "forged"
    assert_received {:github_issue, "Corrigir o gargalo", two}
    assert two =~ second["verification"]
    refute two =~ "imaginary"
    refute two =~ guide
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
              "project_guide" => "",
              "review_method" => "performance",
              "verification" => "Comparar o p95 com a mesma carga antes e depois.",
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

    # Where no agent watches the project the runner cannot be picked: the
    # option is off, the note says why and opens Projects to set one up.
    assert has_element?(view, "input#composer-executor-dsh[disabled]")

    assert has_element?(
             view,
             "#composer-executor-blocked",
             "Nenhum agente cuida deste projeto, então o DeepSeek fica de fora aqui."
           )

    assert has_element?(
             view,
             "#composer-executor-blocked button[phx-value-panel=settings][phx-value-section=projects]",
             "Configurar um agente"
           )

    view
    |> element("#composer-form")
    |> render_change(%{"text" => "Refazer o placar", "executor" => "dsh"})

    assert has_element?(view, "label[for=composer-executor-codex].is-on")
    refute has_element?(view, "label[for=composer-executor-dsh].is-on")

    submit(view, %{"text" => "Refazer o placar", "executor" => "codex"})

    assert_received {:issue, sent}
    refute sent["body"] =~ "@example-bot"
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
    assert body =~ ~r/@example-bot\z/
  end

  test "a single request has no kind and no size", %{conn: conn} do
    github()
    view = open_composer(conn)
    type(view, "Corrigir o contador")
    submit(view, %{"text" => "Corrigir o contador"})

    assert %Task{work_type: nil, size: nil} = Repo.one(Task)
    refute has_element?(view, "#composer-receipt .ab-work")
  end

  test "answers stay paired through AI retries, distinct rounds, review and explicit publication",
       %{conn: conn} do
    counter = github(capture: self())
    test_pid = self()
    q1 = "Quem reage?"
    q2 = "E a câmera?"
    q3 = "E o HUD?"
    extra = "Qual cena?"
    k = &AgentBoard.Intake.question_key/1
    request = "Revisar impacto"

    script(fn
      %{name: :refine_request, prompt: prompt} ->
        send(test_pid, {:refine, prompt})

        cond do
          prompt =~ "HUD visível" -> Scripted.answer(%{@refined | "open_questions" => [extra]})
          prompt =~ "Parada" -> Scripted.answer(%{@refined | "blocking_questions" => [q3]})
          true -> Scripted.answer(%{@refined | "blocking_questions" => [q1, q2]})
        end

      %{name: :propose_tasks, prompt: prompt} ->
        send(test_pid, {:proposal, prompt})
        Scripted.answer(@tasks)
    end)

    view = open_composer(conn)
    type(view, "  " <> request)
    split(view)
    assert_received {:refine, _}
    assert has_element?(view, "#composer-answer-submit[disabled]")
    refute has_element?(view, "#composer-submit")
    refute has_element?(view, "#composer-split")

    round = fn ->
      html = view |> element("input[name=round]") |> render()
      [_, value] = Regex.run(~r/value="([0-9]+)"/, html)
      value
    end

    first = %{
      "round" => round.(),
      "text" => "  " <> request,
      "clarify" => %{k.(q1) => "Só o alvo"}
    }

    submit(view, first)
    assert has_element?(view, "#composer-error")
    refute_received {:refine, _}

    filled = put_in(first, ["clarify", k.(q2)], "Parada")
    submit(view, put_in(filled, ["clarify", "forged"], "unknown question"))
    assert_received {:refine, prompt}
    assert prompt =~ "Quem reage? — Só o alvo"
    assert prompt =~ "E a câmera? — Parada"
    refute prompt =~ "unknown question"
    assert has_element?(view, "#composer-clarify-#{k.(q3)}")
    render_hook(view, "composer_answer", filled)
    refute_received {:refine, _}
    second = %{"round" => round.(), "text" => request, "clarify" => %{k.(q3) => "HUD visível"}}
    submit(view, second)
    assert_received {:refine, last}
    assert_received {:proposal, proposal}

    for text <- [last, proposal],
        expected <- [
          request,
          "Quem reage? — Só o alvo",
          "E a câmera? — Parada",
          "E o HUD? — HUD visível"
        ],
        do: assert(text =~ expected)

    assert has_element?(view, "#composer-applied", q2)
    assert has_element?(view, "#composer-open-questions", "Decisões opcionais")
    refute view |> element("#composer-text") |> render() =~ "Parada"
    render_hook(view, "composer_answer", second)
    assert Agent.get(counter, & &1) == 100
    edits = %{"tasks" => ["0"], "shared_context" => %{"answers" => %{k.(extra) => "Fase 1"}}}
    view |> element("#composer-form") |> render_change(edits)
    refute_received {:refine, _}
    refute_received {:proposal, _}
    assert Agent.get(counter, & &1) == 100
    submit(view, Map.merge(edits, %{"tasks" => ["0"], "text" => request}))
    assert_received {:github_issue, _, posted}

    for value <- [
          "Quem reage? — Só o alvo",
          "E a câmera? — Parada",
          "E o HUD? — HUD visível",
          "Qual cena? — Fase 1"
        ],
        do: assert(posted =~ value)

    assert Agent.get(counter, & &1) == 101
  end

  test "a failed AI regeneration keeps the reviewed proof and selection without publishing", %{
    conn: conn
  } do
    counter = github()

    script(fn
      %{name: :refine_request} ->
        Scripted.answer(%{@refined | "open_questions" => ["Com qual carga?"]})

      %{name: :propose_tasks} ->
        Scripted.answer(@tasks)
    end)

    view = open_composer(conn)
    type(view, "O board está lento")
    split(view)

    edits = %{
      "tasks" => ["1"],
      "shared_context" => %{
        "answers" => %{AgentBoard.Intake.question_key("Com qual carga?") => "50 tickets"}
      },
      "task_edits" => %{
        "1" => %{
          "title" => "Corrigir o gargalo",
          "body" => "Atacar a causa.",
          "acceptance" => "Medir p95",
          "verification" => "Comparar a mesma fila"
        }
      }
    }

    view |> element("#composer-form") |> render_change(edits)
    script(fn _ -> Scripted.malformed() end)
    split(view)

    assert has_element?(
             view,
             "#composer-error",
             "A proposta anterior e suas edições continuam disponíveis."
           )

    assert has_element?(view, "#composer-proof-1", "Comparar a mesma fila")
    assert has_element?(view, "#composer-task-1[checked]")
    refute has_element?(view, "#composer-task-0[checked]")
    assert Agent.get(counter, & &1) == 100
  end

  test "a malformed answer is a named failure with a retry, not inspect/1", %{conn: conn} do
    github()
    script(fn _request -> Scripted.malformed() end)

    view = open_composer(conn)
    type(view, "Pedido com resposta quebrada")
    split(view)

    assert has_element?(view, "#composer-error", "fora do formato esperado")
    refute view |> element("#composer-form") |> render() =~ "malformed_output"
    assert has_element?(view, "#composer-error button", "Tentar novamente com IA")
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
    view |> element("#composer-error button", "Tentar novamente com IA") |> render_click()
    render_async(view, 2000)

    refute has_element?(view, "#composer-error")
    assert has_element?(view, "#composer-form", "2 tarefas prontas para revisão")
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
    assert has_element?(view, "#composer-error button", "Tentar novamente com IA")
    refute has_element?(view, "#composer-progress")
    refute has_element?(view, "#composer-form", "tarefas prontas para revisão")
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
    refute has_element?(view, "#composer-form", "tarefas prontas para revisão")
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
    assert has_element?(view, "#composer-form", "2 tarefas prontas para revisão")
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

    assert has_element?(view, "#composer-form", "Nenhuma tarefa para revisar")

    view |> element("#composer-unsplit") |> render_click()
    assert Agent.get(counter, & &1) == 100
    assert has_element?(view, "#composer-submit", "Criar issue no GitHub")
    submit(view, %{"text" => "Pedido sem tarefas"})

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

    assert has_element?(view, "#composer-retry-confirm", "Corrigir o gargalo")
    refute has_element?(view, "#composer-retry-confirm", "Medir o carregamento")
    first = Repo.one!(Task)
    Repo.update!(Ecto.Changeset.change(first, state: "done"))

    view |> element("#composer-receipt button", "Tentar as 1 que falharam") |> render_click()
    render_async(view, 2000)

    assert Repo.one!(
             from d in AgentBoard.Actions.Decision,
               where: d.action == "create_tasks",
               order_by: [desc: d.id],
               limit: 1
           ).detail == "1 de 1 não entraram"

    counter = github(start: 101)
    view |> element("#composer-receipt button", "Tentar as 1 que falharam") |> render_click()
    render_async(view, 2000)

    assert has_element?(view, "#composer-receipt", "1 pedido na fila; 1 já estava na fila")
    assert Repo.aggregate(Task, :count) == 2
    # The two tasks, and the issue that groups them once both exist.
    assert Agent.get(counter, & &1) == 103

    titles = Repo.all(from t in Task, select: t.title, order_by: t.id)
    assert titles == ["Medir o carregamento", "Corrigir o gargalo"]
    dependent = Repo.get_by!(Task, number: 102)
    assert dependent.body =~ "**Depende de:** #101"

    assert Repo.get_by!(AgentBoard.Board.TaskDependency, task_id: dependent.id).blocked_by_task_id ==
             first.id
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

    assert has_element?(view, "#composer-form", "2 tarefas prontas para revisão")
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
