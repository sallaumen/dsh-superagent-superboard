defmodule AgentBoardWeb.BoardWorkpadTest do
  @moduledoc """
  A waiting ticket is read through the agent's workpad: Pergunta makes it a
  question without any "?", Validação is the local CI, checked against the
  PR's head. The runner's state comes from a fixture sqlite.
  """
  use AgentBoardWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo, TicketPoller}
  alias AgentBoard.Board.{PullRequest, Task}

  @head "44653e8abcdef0123456789abcdef0123456789a"

  # The state database is a global knob, so this module is not async: the
  # async modules have all finished when it runs.
  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "board-workpad-#{System.pid()}-#{System.unique_integer([:positive])}.sqlite"
      )

    File.rm(path)
    previous = Application.get_env(:agent_board, :state_db)
    Application.put_env(:agent_board, :state_db, path)

    on_exit(fn ->
      for suffix <- ["", "-wal", "-shm"], do: File.rm(path <> suffix)

      if previous,
        do: Application.put_env(:agent_board, :state_db, previous),
        else: Application.delete_env(:agent_board, :state_db)
    end)

    {:ok, path: path}
  end

  test "a waiting ticket whose workpad asks lands in Precisa de você as a question", %{
    conn: conn,
    path: path
  } do
    {:ok, repo} = Board.add_repository("fixture", "workpad")
    Board.log_event(repo.id, "sync", "fixture/workpad", %{"errors" => 0})
    task = task(repo, 7, "Boss fight")
    write_ticket(path, waiting(7, "Waiting for the owner before touching the boss.", []))

    workpad(task, """
    ### Plano
    Trocar a arena.

    ### Validação

    ### Pergunta
    Devo manter o boss na arena ou tirar

    ### Bloqueio
    """)

    TicketPoller.poll()
    assert Repo.get!(Task, task.id).state == "question"

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/workpad")

    assert has_element?(view, "#sec-needs #task-#{task.id}", "O agente perguntou:")

    assert has_element?(
             view,
             "#sec-needs #task-#{task.id}",
             "Devo manter o boss na arena ou tirar"
           )

    assert has_element?(view, "#sec-needs #task-#{task.id} button", "Responder")
  end

  test "a waiting ticket with its PR shows the workpad's gate as the local CI", %{
    conn: conn,
    path: path
  } do
    {:ok, repo} = Board.add_repository("fixture", "workpad")
    Board.log_event(repo.id, "sync", "fixture/workpad", %{"errors" => 0})
    task = task(repo, 7, "Boss fight")
    pull(repo, 28, @head)
    write_ticket(path, waiting(7, "PR #28 opened; waiting for review.", [28]))

    workpad(task, """
    ### Plano
    Abrir o https://github.com/fixture/workpad/pull/28.

    ### Validação
    mix precommit: passou (326 testes) em 44653e8

    ### Pergunta

    ### Bloqueio
    """)

    TicketPoller.poll()
    assert Repo.get!(Task, task.id).state == "ready"

    {:ok, view, _html} = live(conn, ~p"/?repo=fixture/workpad")

    assert has_element?(view, "#sec-needs #task-#{task.id}", "PR #28 pronto para revisão")
    assert has_element?(view, "#sec-needs #task-#{task.id} .ab-tag--agent", "CI local ok")

    assert has_element?(
             view,
             ~s|#sec-needs #task-#{task.id} .ab-tag[title*="passou (326 testes) em 44653e8"]|
           )
  end

  test "a comment quoting a PR number no table holds does not stop the board", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "workpad")
    task = task(repo, 7, "Boss fight")
    Repo.update!(Task.changeset(task, %{state: "ready"}))

    {:ok, _} =
      Board.upsert_comment(
        task,
        %{
          "id" => 2,
          "user" => %{"login" => "someone"},
          "body" => "see https://github.com/a/b/pull/9999999999"
        },
        "sallaumen-agent"
      )

    {:ok, view, html} = live(conn, ~p"/?repo=fixture/workpad")
    assert html =~ "Boss fight"

    render_patch(view, ~p"/?repo=fixture/workpad&panel=conversation&task=#{task.id}")
    assert Process.alive?(view.pid)
  end

  test "a ticket row in another shape does not stop the board", %{conn: conn, path: path} do
    {:ok, repo} = Board.add_repository("fixture", "workpad")
    task(repo, 7, "Boss fight")

    write_ticket(path, %{
      "channels" => [%{"address" => %{"number" => "abc"}}],
      "assignments" => %{"unexpected" => true},
      "ended" => "x"
    })

    {:ok, view, html} = live(conn, ~p"/?repo=fixture/workpad")

    assert html =~ "Boss fight"
    assert Process.alive?(view.pid)
  end

  defp task(repo, number, title) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: number,
      title: title,
      state: "queued"
    })
    |> Repo.insert!()
  end

  defp pull(repo, number, head) do
    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: number,
      title: "Replace the arena",
      state: "open",
      checks_state: "failure",
      checks_failed: "gates",
      head_sha: head,
      url: "https://github.com/fixture/workpad/pull/#{number}"
    })
    |> Repo.insert!()
  end

  defp workpad(task, sections) do
    {:ok, _} =
      Board.upsert_comment(
        task,
        %{
          "id" => 1,
          "user" => %{"login" => "sallaumen-agent"},
          "body" =>
            "This is by an automated agent, not a human.\n\n## Relatório do agente\n\n" <>
              sections
        },
        "sallaumen-agent"
      )
  end

  defp waiting(number, summary, own_threads) do
    %{
      "mandate" => %{"basis" => %{"scope" => %{"number" => number}}},
      "channels" => [
        %{
          "address" => %{
            "url" => "https://github.com/fixture/workpad/issues/#{number}",
            "number" => number
          }
        }
      ],
      "follows" => Enum.map(own_threads, &%{"own" => true, "thread" => "github:#{&1}"}),
      "assignments" => [
        %{
          "state" => "running",
          "startedAt" => "2026-11-07T10:00:00.000Z",
          "idleAt" => nil,
          "report" => %{
            "state" => "waiting",
            "summary" => summary,
            "at" => "2026-11-07T10:05:00.000Z"
          }
        }
      ],
      "execution" => %{"directory" => "/does/not/exist"}
    }
  end

  defp write_ticket(path, ticket) do
    {:ok, db} = Exqlite.Sqlite3.open(path)
    :ok = Exqlite.Sqlite3.execute(db, "create table ticket (value text);")
    json = ticket |> Jason.encode!() |> String.replace("'", "''")
    :ok = Exqlite.Sqlite3.execute(db, "insert into ticket (value) values ('" <> json <> "')")
    Exqlite.Sqlite3.close(db)
  end
end
