defmodule AgentBoardWeb.VoiceCommandsTest do
  @moduledoc "Read-only command resolution from the saved board."
  use AgentBoardWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{PullRequest, Task}
  alias AgentBoardWeb.VoiceCommands

  test "recognizes specific Portuguese and English commands without matching actions" do
    assert VoiceCommands.parse("Abrir atividade") == {:panel, "activity"}
    assert VoiceCommands.parse("Show AI calls") == {:panel, "ai"}

    assert VoiceCommands.parse("Trocar para repo sallaumen/agent-board") ==
             {:repository, "sallaumen/agent-board"}

    assert VoiceCommands.parse("Abra tarefa #42") == {:task, 42}
    assert VoiceCommands.parse("Find PR 71") == {:pull_request, 71}
    assert VoiceCommands.parse("O que está bloqueado?") == :blocked
    assert VoiceCommands.parse("show blocked tasks") == :blocked
    assert VoiceCommands.parse("Arquive tarefa 42") == :unknown
    assert VoiceCommands.parse("Crie uma tarefa nova") == :unknown
  end

  test "repository selection accepts only a tracked repository" do
    {:ok, repo} = Board.add_repository("sallaumen", "agent-board")
    context = %{repos: [repo]}

    assert %{result: %{kind: :success}, path: "/?repo=sallaumen%2Fagent-board"} =
             VoiceCommands.resolve("repo sallaumen/agent-board", context)

    assert %{result: %{kind: :unknown}, path: nil} =
             VoiceCommands.resolve("repo other/private", context)
  end

  test "exact task lookup opens the saved task even if its card was not loaded" do
    {:ok, repo} = Board.add_repository("fixture", "long-board")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 81,
        title: "Older task",
        state: "queued"
      })
      |> Repo.insert!()

    context = %{repo: repo, sync_event: nil}

    assert %{
             result: %{kind: :success, text: text, as_of: at, source: "Task record updated"},
             path: path
           } = VoiceCommands.resolve("tarefa #81", context)

    assert text =~ "Older task"
    assert at == task.updated_at
    assert path =~ "task=#{task.id}"
  end

  test "PR lookup stays in the voice panel with an explicit saved link" do
    {:ok, repo} = Board.add_repository("fixture", "pulls")

    pull =
      %PullRequest{}
      |> PullRequest.changeset(%{
        repository_id: repo.id,
        number: 72,
        title: "A saved change",
        state: "merged",
        url: "https://github.com/fixture/pulls/pull/72"
      })
      |> Repo.insert!()

    assert %{result: result, path: nil} =
             VoiceCommands.resolve("find PR 72", %{repo: repo, sync_event: nil})

    assert result.text =~ "Saved state: merged"
    assert result.url == pull.url
    assert result.as_of == pull.updated_at
    assert result.source == "PR record updated"

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 73,
      title: "Untrusted link",
      state: "open",
      url: "javascript:alert(1)"
    })
    |> Repo.insert!()

    assert %{result: %{url: nil}} =
             VoiceCommands.resolve("PR 73", %{repo: repo, sync_event: nil})
  end

  test "status distinguishes a completed sync from a failed attempt" do
    {:ok, repo} = Board.add_repository("fixture", "status")
    at = DateTime.truncate(DateTime.utc_now(), :second)
    board = %{task_counts: %{running: 1, ready: 2, blocked: 3, queued: 4}}

    synced = %{repo: repo, board: board, sync_event: %{kind: "sync", inserted_at: at}}
    failed = %{repo: repo, board: board, sync_event: %{kind: "sync_error", inserted_at: at}}

    assert %{result: %{text: text, as_of: ^at, source: "Last completed sync"}} =
             VoiceCommands.resolve("status", synced)

    assert text =~ "3 blocked"
    assert text =~ "Last completed sync"

    assert %{result: %{text: failed_text, as_of: nil}} =
             VoiceCommands.resolve("status", failed)

    assert failed_text =~ "showing saved data of unknown age"
  end

  test "blocked answer names loaded cards while keeping the exact total" do
    {:ok, repo} = Board.add_repository("fixture", "blocked")

    board = %{
      task_counts: %{running: 0, ready: 0, blocked: 4, queued: 0},
      blocked: [%{number: 7, title: "Fix failing check"}]
    }

    assert %{result: %{text: text, as_of: nil}} =
             VoiceCommands.resolve("o que está bloqueado?", %{
               repo: repo,
               board: board,
               sync_event: nil
             })

    assert text =~ "4 blocked tasks"
    assert text =~ "#7 Fix failing check"
    assert text =~ "No sync yet"
  end

  test "unknown text is retained as a draft and cannot act on a task" do
    assert %{result: %{kind: :unknown, text: text}, path: nil} =
             VoiceCommands.resolve("pare a tarefa 42", %{})

    assert text =~ "Your draft is still here"
  end

  test "a question draft becomes an ask intent only without a read-only match" do
    assert VoiceCommands.parse("As tarefas estão travadas?") ==
             {:ask, "As tarefas estão travadas?"}

    assert VoiceCommands.parse("perguntar o que esta bloqueado") ==
             {:ask, "o que esta bloqueado"}

    assert VoiceCommands.parse("ask why the sync failed") == {:ask, "why the sync failed"}
    assert VoiceCommands.parse("**") == :unknown
    # A known read-only command keeps precedence over the question shape.
    assert VoiceCommands.parse("O que está bloqueado?") == :blocked
  end

  test "asking without an open task explains the requirement" do
    assert %{result: %{kind: :error, text: text}, path: nil} =
             VoiceCommands.resolve("perguntar qualquer coisa", %{conversation: nil})

    assert text =~ "Open a task first"
  end

  test "asking with an open task proposes the confirmed ask" do
    task = %Task{number: 12, title: "Keep this task"}

    assert %{result: %{kind: :ask, question: "qual o estado?", task_number: 12}, path: nil} =
             VoiceCommands.resolve("qual o estado?", %{conversation: task})
  end

  test "a confirmed voice ask posts the question to the open task", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "ask-voice")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 12,
        title: "Ask this task",
        state: "queued"
      })
      |> Repo.insert!()

    previous = Application.get_env(:agent_board, :github_client)
    on_exit(fn -> Application.put_env(:agent_board, :github_client, previous) end)

    Application.put_env(:agent_board, :github_client, fn ->
      Req.new(
        base_url: "https://api.github.com",
        plug: {Req.Test, AgentBoardWeb.VoiceCommandsTest},
        retry: false
      )
    end)

    Req.Test.stub(AgentBoardWeb.VoiceCommandsTest, fn conn ->
      Req.Test.json(conn, %{"id" => 9001, "user" => %{"login" => "sallaumen"}})
    end)

    {:ok, view, _html} =
      live(conn, AgentBoardWeb.BoardNavigation.path(repo, "conversation", task.id))

    render_hook(view, "voice_transcript", %{"text" => "qual o estado da tarefa?"})

    view
    |> form("#voice-command-form", %{"text" => "qual o estado da tarefa?"})
    |> render_submit()

    assert render(view) =~ "Ask task #12: qual o estado da tarefa?"

    view |> element("button", "Ask the agent") |> render_click()

    html = render(view)
    assert html =~ "Question sent"
    assert Repo.get_by(AgentBoard.Board.Comment, task_id: task.id, kind: "user")
  end

  test "the reviewed command form opens a read-only panel", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "read-only")
    {:ok, view, _html} = live(conn, "/?repo=fixture/read-only")

    render_hook(view, "voice_transcript", %{"text" => "abrir atividade"})
    assert render(view) =~ ~s(data-panel="voice")

    view
    |> form("#voice-command-form", %{"text" => "abrir atividade"})
    |> render_submit()

    assert render(view) =~ ~s(data-panel="activity")
  end

  test "task action command remains editable and only prepares a confirmation", %{conn: conn} do
    {:ok, repo} = Board.add_repository("fixture", "safe-command")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 12,
        title: "Keep this task",
        state: "queued"
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, "/?repo=fixture/safe-command")
    render_hook(view, "voice_transcript", %{"text" => "archive task 12"})

    view
    |> form("#voice-command-form", %{"text" => "archive task 12"})
    |> render_submit()

    html = render(view)
    assert html =~ ~s(data-panel="voice")
    assert html =~ "archive task 12"
    assert html =~ "Confirm archive"
    assert html =~ "Hides this task from the board and keeps its history"
    assert Repo.get!(Task, task.id).state == "queued"
  end

  test "invalid command payload reports an error without crashing the LiveView", %{conn: conn} do
    {:ok, _repo} = Board.add_repository("fixture", "invalid-command")
    {:ok, view, _html} = live(conn, "/?repo=fixture/invalid-command")
    render_hook(view, "voice_transcript", %{"text" => "status"})

    render_hook(view, "voice_command", %{"text" => nil})

    assert render(view) =~ "Command text is missing"
    assert render(view) =~ "status"
  end
end
