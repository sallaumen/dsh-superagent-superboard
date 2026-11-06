defmodule AgentBoardWeb.InspectorTest do
  @moduledoc "The task inspector: tabs, attributed calls, the linked PR and the quiet actions."
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoard.{AI, Board, Repo}
  alias AgentBoard.AI.Call
  alias AgentBoard.Board.{Comment, PullRequest, Task}
  alias AgentBoardWeb.BoardComponents.Inspector
  alias AgentBoardWeb.BoardNavigation

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
    assert has_element?(view, "#conversation", "CI remoto falhou")
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
    refute render(view) =~ "dsh-superagent"
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
end
