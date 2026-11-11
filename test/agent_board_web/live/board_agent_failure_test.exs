defmodule AgentBoardWeb.BoardAgentFailureTest do
  @moduledoc """
  An agent failure on the board: a retry the board makes by itself is a row
  in Agora; a failure that needs the owner is an item with the step to take;
  the detail explains it and acts only after a confirmation; a dead
  orchestrator is one item with a way to restart it.
  """
  use AgentBoardWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{Event, Task}

  @orchestrator AgentBoardWeb.BoardAgentFailureTest.Orchestrator
  @github AgentBoardWeb.BoardAgentFailureTest.GitHub
  @transport "LlmError: DeepSeek Messages transport failed"

  defp ticket(number, summary) do
    Jason.encode!(%{
      "id" => "t#{number}",
      "title" => "Ticket #{number}",
      "mandate" => %{"basis" => %{"scope" => %{"number" => number}}},
      "channels" => [
        %{
          "address" => %{
            "number" => number,
            "url" => "https://github.com/fixture/failures/issues/#{number}"
          }
        }
      ],
      "execution" => %{"directory" => "/nonexistent/board-agent-failure-#{number}"},
      "assignments" => [
        %{
          "id" => "a#{number}",
          "state" => "running",
          "startedAt" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -120, :second)),
          "report" => %{
            "state" => "failed",
            "summary" => summary,
            "at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -30, :second))
          }
        }
      ]
    })
  end

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "board-agent-failure-#{System.pid()}-#{System.unique_integer([:positive])}.sqlite"
      )

    {:ok, db} = Exqlite.Sqlite3.open(path)
    :ok = Exqlite.Sqlite3.execute(db, "create table ticket (value text);")

    for value <- [
          ticket(70, @transport),
          ticket(71, "Tests failed: 3 failures in board_test.exs")
        ] do
      {:ok, stmt} = Exqlite.Sqlite3.prepare(db, "insert into ticket (value) values (?1)")
      :ok = Exqlite.Sqlite3.bind(stmt, [value])
      :done = Exqlite.Sqlite3.step(db, stmt)
      :ok = Exqlite.Sqlite3.release(db, stmt)
    end

    Exqlite.Sqlite3.close(db)

    saved =
      for key <- [:state_db, :orchestrator_client, :agent_starter, :github_client],
          into: %{},
          do: {key, Application.get_env(:agent_board, key)}

    Application.put_env(:agent_board, :state_db, path)
    # The LiveView and the components' async work run in other processes.
    Req.Test.set_req_test_to_shared()

    on_exit(fn ->
      Req.Test.set_req_test_to_private()
      for suffix <- ["", "-wal", "-shm"], do: File.rm(path <> suffix)

      for {key, value} <- saved do
        if value,
          do: Application.put_env(:agent_board, key, value),
          else: Application.delete_env(:agent_board, key)
      end
    end)

    {:ok, repo} = Board.add_repository("fixture", "failures")
    Board.log_event(repo.id, "sync", "fixture/failures", %{"errors" => 0})
    retrying = insert_task(repo, 70, "Retry by itself", "retrying")
    blocked = insert_task(repo, 71, "Needs the owner", "blocked")

    %{repo: repo, retrying: retrying, blocked: blocked}
  end

  defp insert_task(repo, number, title, state) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: number,
      title: title,
      state: state,
      url: "https://github.com/fixture/failures/issues/#{number}"
    })
    |> Repo.insert!()
  end

  # The orchestrator answers its state and accepts a retry, or is down.
  defp orchestrator(:up) do
    test = self()

    Application.put_env(:agent_board, :orchestrator_client, fn ->
      Req.new(
        base_url: "http://orchestrator.test/orchestrator/api",
        plug: {Req.Test, @orchestrator},
        retry: false
      )
    end)

    Req.Test.stub(@orchestrator, fn conn ->
      send(test, {:orchestrator, conn.method, conn.request_path})

      case conn.method do
        "GET" ->
          Req.Test.json(conn, %{"load" => %{"running" => 1, "queued" => 0, "maxWorkers" => 3}})

        "POST" ->
          # Holds the answer until the test has seen the loading state.
          send(test, {:holding, self()})

          receive do
            :answer -> Req.Test.json(conn, %{"retried" => true})
          after
            2_000 -> Req.Test.json(conn, %{"retried" => true})
          end
      end
    end)
  end

  defp orchestrator(:down) do
    Application.put_env(:agent_board, :orchestrator_client, fn ->
      Req.new(
        base_url: "http://orchestrator.test/orchestrator/api",
        plug: {Req.Test, @orchestrator},
        retry: false
      )
    end)

    Req.Test.stub(@orchestrator, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
  end

  test "a retry the board makes is in Agora; a failure that needs the owner is in Precisa de você",
       %{conn: conn, retrying: retrying, blocked: blocked} do
    orchestrator(:up)
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/failures")

    assert has_element?(
             view,
             "#sec-now #task-#{retrying.id}.ab-run--retry",
             "Falha de rede ao chamar o modelo."
           )

    assert has_element?(view, "#sec-now #task-#{retrying.id}", "Nova tentativa automática")
    assert has_element?(view, "#sec-now .ab-sec__count", "1 em nova tentativa")
    refute has_element?(view, "#sec-needs #task-#{retrying.id}")

    assert has_element?(
             view,
             "#sec-needs #task-#{blocked.id}",
             "Não parece falha de rede: leia o erro no detalhe antes de tentar de novo."
           )
  end

  test "the detail explains the failure and retries only after a confirmation",
       %{conn: conn, blocked: blocked, repo: repo} do
    orchestrator(:up)
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/failures")
    view |> element("#sec-needs #task-#{blocked.id} button", "Ver detalhe") |> render_click()

    assert has_element?(view, "#agent-failure h3", "O agente relatou uma falha")
    assert has_element?(view, "#agent-failure .ab-fail__error", "Tests failed: 3 failures")
    assert has_element?(view, "#agent-failure .ab-fail__attempts li", "falhou: Tests failed")

    view |> element("#retry-#{blocked.id}-trigger", "Tentar de novo") |> render_click()

    assert has_element?(
             view,
             "#retry-#{blocked.id} .ab-act__question",
             "Pedir ao agente uma nova tentativa de #71 agora?"
           )

    refute_received {:orchestrator, "POST", _path}

    view |> element("#retry-#{blocked.id}-confirm") |> render_click()
    assert_receive {:holding, request}
    assert has_element?(view, "#retry-#{blocked.id} .ab-act__busy", "Pedindo ao agente")
    send(request, :answer)

    assert render_async(view) =~ "Nova tentativa pedida."
    assert has_element?(view, "#retry-#{blocked.id} .ab-act__result", "Nova tentativa pedida.")
    assert_received {:orchestrator, "POST", "/orchestrator/api/tickets/t71/retry"}

    assert Repo.exists?(
             from e in Event,
               where: e.repository_id == ^repo.id and e.kind == "agent_retry_manual"
           )
  end

  test "the card in Precisa de você asks for the attempt itself", %{conn: conn, blocked: blocked} do
    orchestrator(:up)
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/failures")

    view |> element("#need-retry-#{blocked.id}-trigger", "Tentar de novo") |> render_click()

    assert has_element?(
             view,
             "#need-retry-#{blocked.id} .ab-act__question",
             "Pedir ao agente uma nova tentativa de #71 agora?"
           )

    refute_received {:orchestrator, "POST", _path}

    view |> element("#need-retry-#{blocked.id}-confirm") |> render_click()
    assert_receive {:holding, request}
    send(request, :answer)

    assert render_async(view) =~ "Nova tentativa pedida."
    assert_received {:orchestrator, "POST", "/orchestrator/api/tickets/t71/retry"}
  end

  test "in English, the retry asks and answers in English", %{blocked: blocked} do
    orchestrator(:up)
    conn = Phoenix.ConnTest.build_conn() |> Plug.Test.put_req_cookie("board_locale", "en")
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/failures")

    view |> element("#need-retry-#{blocked.id}-trigger") |> render_click()

    assert has_element?(
             view,
             "#need-retry-#{blocked.id} .ab-act__question",
             "Ask the agent for another attempt on #71 now?"
           )

    view |> element("#need-retry-#{blocked.id}-confirm") |> render_click()
    assert_receive {:holding, request}
    send(request, :answer)

    # The effect runs in a task; its answer still follows the confirmation.
    html = render_async(view)
    assert html =~ "New attempt requested."
    refute html =~ "Nova tentativa pedida."
    assert_received {:orchestrator, "POST", "/orchestrator/api/tickets/t71/retry"}
  end

  test "cancel leaves everything as it was", %{conn: conn, blocked: blocked} do
    orchestrator(:up)
    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/failures")
    view |> element("#sec-needs #task-#{blocked.id} button", "Ver detalhe") |> render_click()

    view |> element("#retry-#{blocked.id}-trigger") |> render_click()
    view |> element("#retry-#{blocked.id} button", "Cancelar") |> render_click()

    assert has_element?(view, "#retry-#{blocked.id}-trigger", "Tentar de novo")
    refute has_element?(view, "#retry-#{blocked.id} .ab-act__question")
    refute_received {:orchestrator, "POST", _path}
  end

  test "Parar asks first, then stops through the board's own action", %{
    conn: conn,
    blocked: blocked
  } do
    orchestrator(:up)

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(base_url: "https://api.github.com", plug: {Req.Test, @github}, retry: false)
    end)

    Req.Test.stub(@github, fn conn -> Req.Test.json(conn, %{"state" => "closed"}) end)

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/failures")
    view |> element("#sec-needs #task-#{blocked.id} button", "Ver detalhe") |> render_click()

    view |> element("#stop-#{blocked.id}-trigger", "Parar") |> render_click()
    refute Repo.get(Task, blocked.id).stopped
    assert has_element?(view, "#stop-#{blocked.id} .ab-act__question", "Parar a tarefa #71")

    view |> element("#stop-#{blocked.id}-confirm", "Parar a tarefa") |> render_click()
    assert Repo.get(Task, blocked.id).stopped
  end

  test "in English, Stop asks in English and the English sentence stops the task", %{
    blocked: blocked
  } do
    orchestrator(:up)

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(base_url: "https://api.github.com", plug: {Req.Test, @github}, retry: false)
    end)

    Req.Test.stub(@github, fn conn -> Req.Test.json(conn, %{"state" => "closed"}) end)

    conn = Phoenix.ConnTest.build_conn() |> Plug.Test.put_req_cookie("board_locale", "en")

    {:ok, view, _html} =
      live(conn, ~p"/?repo=fixture/failures&task=#{blocked.id}&panel=conversation")

    # The lanes, written by the domain layer, follow the interface language too.
    html = render(view)
    assert html =~ "Needs you"
    refute html =~ "Precisa de você"
    refute html =~ "Ver detalhe"
    refute html =~ "Todas"
    refute html =~ "Bloqueado"

    view |> element("#stop-#{blocked.id}-trigger") |> render_click()
    assert has_element?(view, "#stop-#{blocked.id} .ab-act__question", "Stop task #71")
    refute has_element?(view, "#stop-#{blocked.id} .ab-act__question", "Parar a tarefa")

    view |> element("#stop-#{blocked.id}-confirm") |> render_click()
    assert Repo.get(Task, blocked.id).stopped
  end

  test "with the orchestrator down, one item says so and restarts it after a confirmation",
       %{conn: conn, blocked: blocked} do
    orchestrator(:down)
    test = self()

    Application.put_env(:agent_board, :agent_starter, fn ->
      send(test, :agent_started)
      {"dsh-superagent already running", 0}
    end)

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/failures")

    assert has_element?(view, "#need-agent-down .ab-need__kind", "Agente fora do ar")
    assert has_element?(view, "#need-agent-down", "Nenhuma tarefa nova começa até ele voltar")
    assert has_element?(view, "#need-agent-down", "2 tarefas esperam ele voltar")
    refute has_element?(view, "#sec-needs #task-#{blocked.id}")

    view |> element("#agent-restart-trigger", "Religar o agente") |> render_click()

    assert has_element?(
             view,
             "#agent-restart .ab-act__question",
             "Religar o agente nesta máquina?"
           )

    refute_received :agent_started

    view |> element("#agent-restart-confirm", "Religar") |> render_click()
    assert render_async(view) =~ "O agente está de pé."
    assert_received :agent_started
  end

  # The runner accepts the connection and does not answer: the tab reads it
  # in the background and keeps the last answer on screen meanwhile.
  test "a runner that does not answer never holds the page", %{conn: conn} do
    test = self()

    Application.put_env(:agent_board, :orchestrator_client, fn ->
      Req.new(
        base_url: "http://orchestrator.test/orchestrator/api",
        plug: {Req.Test, @orchestrator},
        retry: false
      )
    end)

    Req.Test.stub(@orchestrator, fn conn ->
      send(test, {:orchestrator_get, self()})

      receive do
        {:answer, running} ->
          Req.Test.json(conn, %{
            "load" => %{"running" => running, "queued" => 0, "maxWorkers" => 3}
          })
      after
        2_000 -> Req.Test.transport_error(conn, :timeout)
      end
    end)

    {elapsed, {:ok, view, _html}} = :timer.tc(fn -> live(conn, ~p"/?repo=fixture/failures") end)
    assert elapsed < 1_000_000

    assert_receive {:orchestrator_get, runner}
    send(runner, {:answer, 2})
    render_async(view)
    assert has_element?(view, ~s([data-key="load"][data-value="2/3/0"]))

    send(view.pid, :board_updated)
    {elapsed, _html} = :timer.tc(fn -> render(view) end)
    assert elapsed < 500_000
    assert_receive {:orchestrator_get, _silent}
    assert has_element?(view, ~s([data-key="load"][data-value="2/3/0"]))
  end
end
