defmodule AgentBoardWeb.VoiceCommandsTest do
  @moduledoc "Read-only command resolution from the saved board."
  use AgentBoardWeb.ConnCase, async: false

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

    assert text =~ "Abra uma tarefa primeiro"

    Gettext.put_locale(AgentBoardWeb.Gettext, "en")

    assert %{result: %{text: english}} =
             VoiceCommands.resolve("ask anything", %{conversation: nil})

    assert english =~ "Open a task first"
  end

  test "asking with an open task proposes the confirmed ask" do
    task = %Task{number: 12, title: "Keep this task"}

    assert %{result: %{kind: :ask, question: "qual o estado?", task_number: 12}, path: nil} =
             VoiceCommands.resolve("qual o estado?", %{conversation: task})
  end
end
