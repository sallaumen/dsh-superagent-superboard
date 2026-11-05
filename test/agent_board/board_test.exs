defmodule AgentBoard.BoardTest do
  @moduledoc "The context: the repositories, the board and the task actions."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{PullRequest, Task}

  test "a repository can be added" do
    assert {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    assert repo.owner == "sallaumen"
    assert repo.name == "arena-rogue"
  end

  test "a repository rejects a slash" do
    assert {:error, changeset} = Board.add_repository("a/b", "c")
    assert changeset.errors[:owner]
  end

  test "the board is empty without repositories" do
    assert {:ok, board} = Board.board(nil)
    assert board.running == []
    assert board.merged == []
  end

  test "the board groups the tasks by state" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    for {number, state} <- [{1, "running"}, {2, "ready"}, {3, "queued"}] do
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: number,
        title: "Task #{number}",
        state: state
      })
      |> Repo.insert!()
    end

    {:ok, board} = Board.board("sallaumen/arena-rogue")
    assert length(board.running) == 1
    assert length(board.ready) == 1
    assert length(board.queued) == 1
  end

  test "the merged column carries the review and CI rollups" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 7,
      title: "Merged",
      state: "merged",
      merged_at: DateTime.utc_now(),
      review_state: "approved",
      checks_state: "success"
    })
    |> Repo.insert!()

    {:ok, board} = Board.board("sallaumen/arena-rogue")
    assert [pr] = board.merged
    assert pr.review_state == "approved"
    assert pr.checks_state == "success"
  end

  test "archiving removes the task from the board" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 9,
        title: "Archive me",
        state: "queued"
      })
      |> Repo.insert!()

    assert {:ok, archived} = Board.archive_task(task)
    assert archived.archived
    assert archived.state == "archived"
  end

  test "resuming brings a task back to the queue" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: 11,
        title: "Resume me",
        state: "stopped",
        stopped: true
      })
      |> Repo.insert!()

    assert {:ok, resumed} = Board.resume_task(task)
    refute resumed.stopped
    assert resumed.state == "queued"
  end

  test "an event is recorded" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    assert {:ok, _} = Board.log_event(repo.id, "sync", "test")
    assert length(Board.events(repo)) == 1
  end
end

defmodule AgentBoard.Board.ConversationTest do
  @moduledoc "The conversation: the comments on a task."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  defp task(repo) do
    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 77,
      title: "Talk to me",
      state: "queued"
    })
    |> Repo.insert!()
  end

  test "a comment is upserted and listed" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    t = task(repo)

    assert {:ok, _} =
             Board.upsert_comment(
               t,
               %{"id" => 1, "user" => %{"login" => "sallaumen-agent"}, "body" => "On it."},
               "sallaumen-agent"
             )

    assert [comment] = Board.comments(t)
    assert comment.kind == "agent"
    assert comment.body == "On it."
  end

  test "a user comment is marked as user" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    t = task(repo)

    assert {:ok, _} =
             Board.upsert_comment(
               t,
               %{"id" => 2, "user" => %{"login" => "sallaumen"}, "body" => "Please add a boss."},
               "sallaumen-agent"
             )

    assert [comment] = Board.comments(t)
    assert comment.kind == "user"
  end

  test "events are limited and newest first", _ctx do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    for n <- 1..25 do
      Board.log_event(repo.id, "sync", "subject-#{n}", %{"n" => n})
    end

    events = Board.events(repo)

    assert length(events) == 20
    assert hd(events).subject == "subject-25"
  end
end
