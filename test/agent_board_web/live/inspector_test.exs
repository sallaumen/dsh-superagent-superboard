defmodule AgentBoardWeb.InspectorTest do
  @moduledoc "The task inspector: tabs, attributed calls, the linked PR and the quiet actions."
  use AgentBoardWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias AgentBoard.{AI, Board, Repo}
  alias AgentBoard.AI.Call
  alias AgentBoard.Board.{Comment, PullRequest, Task}
  alias AgentBoard.Intake.IssueBody
  alias AgentBoardWeb.BoardComponents.Inspector
  alias AgentBoardWeb.BoardNavigation

  test "the English task conversation keeps writing in place", %{conn: _conn} do
    {:ok, repo} = Board.add_repository("fixture", "inspector-english")
    task = task(repo, 26, "Review the result", "done")

    {:ok, view, _html} =
      live(Phoenix.ConnTest.build_conn(), BoardNavigation.path(repo, "conversation", task.id))

    assert has_element?(view, "#conversation[aria-label='Task #26 details']")
    assert has_element?(view, "#conversation .ab-status", "Merged")
    assert has_element?(view, "#inspector-tab-conversa", "Conversation")
    assert has_element?(view, "#inspector-tab-atividade", "Activity")
    assert has_element?(view, "#inspector-tab-chamadas", "AI calls")
    assert has_element?(view, "#ask-agent textarea[aria-label='Message to the agent']")
    refute has_element?(view, "#ask-agent button[aria-label='Dictate by voice']")
  end

  test "the tabs switch in place and the calls are the task's own", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "inspector")
    task = task(repo, 25, "Salvar replays", "ready")

    call(repo, task, "claude-opus", 18_200, 1_100, 310_000, 6_400)
    call(repo, task, "claude-haiku", 3_200, 200, 0, 800)

    {:ok, view, _html} = live(conn, BoardNavigation.path(repo, "conversation", task.id))

    assert has_element?(view, "#conversation-title", "Salvar replays")
    assert has_element?(view, "#conversation", "Conversa")

    view |> element("#conversation button", "Chamadas de IA") |> render_click()
    assert has_element?(view, "#conversation", "claude-opus")
    assert has_element?(view, "#conversation", "18.2k")
    assert has_element?(view, "#conversation", "—")
    assert has_element?(view, "#conversation", "≥ $0.31")
    assert has_element?(view, "#conversation", "Chamadas feitas pelo board")

    view |> element("#conversation button", "Atividade") |> render_click()
    assert has_element?(view, "#conversation", "Entrou na fila")

    view |> element("#conversation button", "PR") |> render_click()
    assert has_element?(view, "#conversation", "Esta tarefa ainda não abriu PR.")
  end

  test "the PR tab follows a GitHub URL in the newest comment", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "inspector-pr")
    task = task(repo, 25, "Salvar replays", "ready")

    %Comment{}
    |> Comment.changeset(%{
      task_id: task.id,
      github_id: 1,
      author: "sallaumen-agent",
      kind: "agent",
      body: "Feito: https://github.com/fixture/inspector-pr/pull/42"
    })
    |> Repo.insert!()

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 42,
      title: "Store replays",
      state: "open",
      url: "https://github.com/fixture/inspector-pr/pull/42",
      checks_state: "failure",
      checks_failed: "gates"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, BoardNavigation.path(repo, "conversation", task.id))
    view |> element("#conversation button", "PR") |> render_click()

    assert has_element?(view, "#conversation", "#42")
    assert has_element?(view, "#conversation", "Store replays")
    assert has_element?(view, "#conversation", "Abrir no GitHub")
    assert has_element?(view, "#conversation", "CI local ?")
  end

  test "the PR tab shows the local gate and explains the remote failure on hover" do
    pr = %PullRequest{
      number: 42,
      title: "Store replays",
      state: "open",
      checks_state: "failure",
      checks_failed: "gates"
    }

    task = %Task{
      number: 25,
      title: "Salvar replays",
      state: "ready",
      updated_at: DateTime.utc_now()
    }

    html =
      render_component(&Inspector.inspector/1, %{
        task: task,
        comments: [],
        tab: "pr",
        activity: [],
        calls: [],
        pr: pr,
        ci: %{
          state: :pass,
          detail: "mix precommit passed (116 tests, Credo 0 issues)",
          remote_blocked: true
        },
        tz_offset: 0,
        live: false
      })

    assert html =~ "CI local ok"
    assert html =~ "GitHub Actions não rodou"
    assert html =~ "mix precommit passed"
  end

  test "the calls tab shows what the executor spent, with a minimum when cache reads have no price" do
    task = %Task{
      number: 25,
      title: "Salvar replays",
      state: "ready",
      updated_at: DateTime.utc_now()
    }

    usage = %{
      status: :measured,
      reason: nil,
      signature: [],
      workers: 1,
      subagents: 1,
      unreadable: 0,
      requests: 334,
      input: 303_380,
      output: 285_621,
      cache_read: 79_984_000,
      cache_write: 0,
      models: ["deepseek-flash"],
      cost: %{micros: 165_486, complete?: false}
    }

    html = render_inspector(task, "chamadas", usage)

    assert html =~ "Executor do agente"
    assert html =~ "1 worker + 1 subagente(s)"
    assert html =~ "303.4k"
    assert html =~ "80.0M"
    assert html =~ "≥ $0.16"
    assert html =~ "o custo é um mínimo"

    assert render_inspector(task, "chamadas", %{usage | status: :none}) =~
             "Nenhuma transcrição do executor"

    assert render_inspector(task, "chamadas", %{usage | status: :unavailable}) =~ "falta o"
    assert render_inspector(task, "chamadas", %{usage | cost: nil}) =~ "custo desconhecido"
  end

  defp render_inspector(task, tab, usage) do
    render_component(&Inspector.inspector/1, %{
      task: task,
      comments: [],
      tab: tab,
      activity: [],
      calls: [],
      usage: usage,
      tz_offset: 0,
      live: false
    })
  end

  test "the task shows its images and links its other files, not the commands", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "inspector-files")
    hash = String.duplicate("c", 64)

    body =
      IssueBody.with_attachments(
        "Refazer o login.",
        [%{name: "a.png", path: "#{hash}/a.png"}, %{name: "m.html", path: "#{hash}/m.html"}],
        repo,
        "pt"
      )

    task = task(repo, 40, "Com anexos", "ready")
    task |> Ecto.Changeset.change(body: body) |> Repo.update!()

    {:ok, view, _html} = live(conn, BoardNavigation.path(repo, "conversation", task.id))

    assert has_element?(
             view,
             "#task-attachments img[src='/attachments/#{repo.id}/#{hash}/a.png']"
           )

    assert has_element?(
             view,
             "#task-attachments a[href='/attachments/#{repo.id}/#{hash}/m.html']",
             "m.html"
           )

    assert has_element?(view, "#conversation", "Refazer o login.")
    refute view |> element("#conversation") |> render() =~ "gh api"
  end

  test "hidden executor markers never reach the conversation", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "inspector-marker")
    task = task(repo, 32, "Visible message", "ready")

    %Comment{}
    |> Comment.changeset(%{
      task_id: task.id,
      github_id: 2,
      author: "sallaumen-agent",
      kind: "agent",
      body: "Entendido. <!-- dsh-superagent:abc123 -->"
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, BoardNavigation.path(repo, "conversation", task.id))

    assert has_element?(view, "#conversation", "Entendido.")
    # Only the conversation: the logs picker lists this machine's real runners.
    refute view |> element("#conversation") |> render() =~ "dsh-superagent"
  end

  test "archiving from the inspector keeps the task reachable", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "inspector-act")
    task = task(repo, 30, "Archive me", "queued")

    {:ok, view, _html} = live(conn, BoardNavigation.path(repo, "conversation", task.id))
    view |> element("#conversation button", "Arquivar") |> render_click()

    assert Repo.get(Task, task.id).archived
    assert has_element?(view, "#conversation button", "Retomar")
  end

  test "a call can be attributed to the task that asked" do
    {:ok, repo} = Board.add_repository("fixture", "call-task")
    task = task(repo, 31, "Ask me", "ready")

    call(repo, task, "deepseek-flash", 10, 2, 100, 50)

    assert [%Call{} = call] = AI.recent_for_task(task.id)
    assert call.task_id == task.id
  end

  test "a blocked task offers a suggested answer and a linked blocker task", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "inspector-unblock")
    task = task(repo, 1417, "Menu central do Ateliê", "blocked")

    %Comment{}
    |> Comment.changeset(%{
      task_id: task.id,
      github_id: 3,
      author: "sallaumen-agent",
      kind: "agent",
      body: """
      ## Relatório do agente

      ### Pergunta
      Devo entregar o menu restrito ao operador?

      ### Bloqueio
      O mapa da #1416 ainda não foi entregue.
      """
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, BoardNavigation.path(repo, "conversation", task.id))

    assert has_element?(view, "#unblock-panel", "Devo entregar o menu restrito")
    assert has_element?(view, "#unblock-panel", "O mapa da #1416")
    assert has_element?(view, "#suggest-unblock", "Sugerir resposta")
    assert has_element?(view, "#open-blocker", "Criar tarefa bloqueadora")

    view |> element("#open-blocker") |> render_click()
    assert has_element?(view, "#blocker-form")
    assert has_element?(view, "#blocker-title")

    view
    |> element("#blocker-form")
    |> render_submit(%{
      "title" => "Desbloquear #1417: decidir perfis",
      "body" => "Resolver #1416."
    })

    assert has_element?(view, "#blocker-confirm", "Desbloquear #1417: decidir perfis")
    assert has_element?(view, "#blocker-confirm", "Criar tarefa")

    view |> element("#blocker-confirm button", "Voltar e editar") |> render_click()

    assert view |> element("#blocker-title") |> render() =~ "Desbloquear #1417: decidir perfis"
    assert view |> element("#blocker-body") |> render() =~ "Resolver #1416."

    assert %AgentBoard.Actions.Decision{
             action: "create_tasks",
             decision: "refused",
             detail: "declined"
           } = Repo.one(from d in AgentBoard.Actions.Decision, order_by: [desc: d.id], limit: 1)
  end

  test "a submitted message appears while GitHub is pending without duplicating its local comment" do
    {:ok, repo} = Board.add_repository("fixture", "inspector-sending")
    task = task(repo, 1418, "Responder ao agente", "blocked")
    sending = %{task_id: task.id, body: "Pode entregar o menu.", ref: make_ref()}

    html = render_conversation(task, [], ask_sending: sending)
    assert length(Regex.scan(~r/class="[^"]*ab-msg--sending/, html)) == 1
    assert html =~ "Pode entregar o menu."
    assert html =~ "Enviando…"
    assert html =~ "issue ##{task.number} do GitHub"
    assert html =~ ~r/<textarea[^>]*disabled/
    refute html =~ "ask-confirm"

    comment =
      %Comment{}
      |> Comment.changeset(%{
        task_id: task.id,
        github_id: -1,
        author: "you",
        kind: "user",
        body: "Pode entregar o menu.\n\n@sallaumen-agent"
      })
      |> Repo.insert!()

    html = render_conversation(task, [comment], ask_sending: sending)
    assert length(Regex.scan(~r/class="[^"]*ab-msg--sending/, html)) == 1
    refute html =~ ~s(data-message-id="sending")
  end

  test "a failed message restores the draft beside a recoverable error" do
    {:ok, repo} = Board.add_repository("fixture", "inspector-send-error")
    task = task(repo, 1419, "Responder ao agente", "blocked")

    html =
      render_conversation(task, [],
        ask_draft: "Preciso dos testes primeiro.",
        ask_error: "A pergunta não chegou ao GitHub. Tente de novo."
      )

    assert html =~ "Preciso dos testes primeiro."
    assert html =~ ~s(role="alert")
    assert html =~ "A pergunta não chegou ao GitHub. Tente de novo."
    refute html =~ "ab-msg--sending"
  end

  defp render_conversation(task, comments, opts) do
    render_component(&Inspector.inspector/1, %{
      task: task,
      comments: comments,
      tab: "conversa",
      activity: [],
      calls: [],
      ask_sending: Keyword.get(opts, :ask_sending),
      ask_draft: Keyword.get(opts, :ask_draft, ""),
      ask_error: Keyword.get(opts, :ask_error),
      tz_offset: 0,
      live: false
    })
  end

  defp task(repo, number, title, state) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: number,
      title: title,
      state: state,
      state_changed_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end

  defp call(_repo, task, model, input, output, cost, duration) do
    %Call{}
    |> Call.changeset(%{
      name: "answer_board_question",
      engine: "deepseek",
      model: model,
      status: "ok",
      input_tokens: input,
      output_tokens: output,
      cost_micros: cost,
      duration_ms: duration,
      task_id: task.id
    })
    |> Repo.insert!()
  end

  test "a typed question survives a tab change and stays on its task", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "inspector")
    first = task(repo, 25, "Salvar replays", "ready")
    other = task(repo, 26, "Outra tarefa", "ready")

    {:ok, view, _html} = live(conn, BoardNavigation.path(repo, "conversation", first.id))

    view |> element("#ask-agent") |> render_change(%{"body" => "Rodou os testes?"})
    view |> element("#conversation button", "Chamadas de IA") |> render_click()
    refute has_element?(view, "#ask-agent")
    view |> element("#conversation button", "Conversa") |> render_click()

    assert view |> element("#ask-body") |> render() =~ "Rodou os testes?"

    render_patch(view, BoardNavigation.path(repo, "conversation", other.id))
    refute view |> element("#ask-body") |> render() =~ "Rodou os testes?"
  end
end
