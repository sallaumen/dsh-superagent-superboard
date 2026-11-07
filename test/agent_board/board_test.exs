defmodule AgentBoard.BoardTest do
  @moduledoc "The context: the repositories, the board and the task actions."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{Comment, PullRequest, Task}

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

  test "saved number lookup stays scoped to its repository and ignores pagination" do
    {:ok, first} = Board.add_repository("fixture", "first")
    {:ok, second} = Board.add_repository("fixture", "second")

    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: first.id,
        kind: "issue",
        number: 81,
        title: "Older task",
        state: "queued"
      })
      |> Repo.insert!()

    for number <- 1..50 do
      %Task{}
      |> Task.changeset(%{
        repository_id: first.id,
        kind: "issue",
        number: number,
        title: "Newer task #{number}",
        state: "queued"
      })
      |> Repo.insert!()
    end

    pull =
      %PullRequest{}
      |> PullRequest.changeset(%{
        repository_id: first.id,
        number: 82,
        title: "Older pull",
        state: "merged"
      })
      |> Repo.insert!()

    assert Board.find_task(first, 81).id == task.id
    {:ok, board} = Board.board("fixture/first")
    refute Enum.any?(board.queued, &(&1.id == task.id))
    assert Board.find_pull_request(first, 82).id == pull.id
    assert Board.find_task(second, 81) == nil
    assert Board.find_pull_request(second, 82) == nil
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

  test "merged pages keep a stable order across tied times, new rows and missing dates" do
    {:ok, repo} = Board.add_repository("fixture", "many-merges")
    now = DateTime.truncate(DateTime.utc_now(), :second)

    for number <- 1..120 do
      %PullRequest{}
      |> PullRequest.changeset(%{
        repository_id: repo.id,
        number: number,
        title: "Merged #{number}",
        state: "merged",
        merged_at: if(rem(number, 31) == 0, do: nil, else: DateTime.add(now, -div(number, 10)))
      })
      |> Repo.insert!()
    end

    {:ok, board} = Board.board("fixture/many-merges")
    assert length(board.merged) == 50
    assert board.merged_has_more

    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: 121,
      title: "Arrived after first page",
      state: "merged",
      merged_at: DateTime.add(now, 1)
    })
    |> Repo.insert!()

    last_first = List.last(board.merged)
    second_rows = Board.merged_page(repo.id, {last_first.merged_at, last_first.id}, 51)
    assert length(second_rows) == 51
    second = Enum.take(second_rows, 50)
    last_second = List.last(second)
    third = Board.merged_page(repo.id, {last_second.merged_at, last_second.id}, 51)

    ids = Enum.map(board.merged ++ second ++ third, & &1.id)
    assert length(ids) == 120
    assert length(Enum.uniq(ids)) == 120
    assert List.last(third).merged_at == nil
  end

  test "active task pages keep total counts and stable cursors when a new task arrives" do
    {:ok, repo} = Board.add_repository("fixture", "many-tasks")

    for number <- 1..120 do
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: number,
        title: "Queued #{number}",
        state: "queued"
      })
      |> Repo.insert!()
    end

    {:ok, board} = Board.board("fixture/many-tasks")
    assert length(board.queued) == 50
    assert board.task_counts.queued == 120
    assert board.task_has_more.queued
    assert board.task_counts.running == 0

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 121,
      title: "New queued task",
      state: "queued"
    })
    |> Repo.insert!()

    last_first = List.last(board.queued)
    second_rows = Board.task_page(repo.id, :queued, {last_first.updated_at, last_first.id}, 51)
    assert length(second_rows) == 51
    second = Enum.take(second_rows, 50)
    last_second = List.last(second)
    third = Board.task_page(repo.id, :queued, {last_second.updated_at, last_second.id}, 51)

    ids = Enum.map(board.queued ++ second ++ third, & &1.id)
    assert length(ids) == 120
    assert length(Enum.uniq(ids)) == 120
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
  alias AgentBoard.Board.{PullRequest, Task}

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

  @workpad """
  This is by an automated agent, not a human.

  ## Relatório do agente

  ### Plano
  Abrir o PR #28. Devo perguntar? Não: isto é o plano.

  ### Validação
  mix precommit: passou (326 testes) em 44653e8

  ### Pergunta
  Devo manter o boss na arena

  ### Bloqueio
  """

  test "the newest agent comment's workpad decides the question, without a question mark" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    t = task(repo)
    agent_comment(t, 1, "Is the API ready?")
    agent_comment(t, 2, @workpad)

    assert Board.agent_asked?(repo.id, 77)

    assert %{question: "Devo manter o boss na arena", validation: %{sha: "44653e8"}} =
             Board.agent_workpad(repo.id, 77)

    assert %{77 => %{question: "Devo manter o boss na arena"}} = Board.agent_workpads(repo.id)
  end

  test "a workpad with an empty Pergunta is not a question, whatever its other text asks" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    t = task(repo)
    agent_comment(t, 1, String.replace(@workpad, "Devo manter o boss na arena\n", ""))

    refute Board.agent_asked?(repo.id, 77)
    assert %{question: nil, plan: plan} = Board.agent_workpad(repo.id, 77)
    assert plan =~ "Devo perguntar?"
  end

  test "without a workpad the newest agent comment asks by its question mark, as before" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")
    t = task(repo)
    agent_comment(t, 1, @workpad)
    agent_comment(t, 2, "On it: which API should the board use?")

    assert Board.agent_asked?(repo.id, 77)
    assert Board.agent_workpad(repo.id, 77) == nil
    assert Board.agent_workpads(repo.id) == %{}

    agent_comment(t, 3, "Done, PR #28 opened.")
    refute Board.agent_asked?(repo.id, 77)
  end

  test "the PR heads come from the sync, absent until it wrote one" do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    for {number, head} <- [{28, "44653e8abcdef0123456789abcdef0123456789a"}, {29, nil}] do
      %PullRequest{}
      |> PullRequest.changeset(%{
        repository_id: repo.id,
        number: number,
        title: "PR #{number}",
        state: "open",
        head_sha: head
      })
      |> Repo.insert!()
    end

    assert Board.pull_heads(repo.id) == %{28 => "44653e8abcdef0123456789abcdef0123456789a"}
  end

  defp agent_comment(task, id, body) do
    {:ok, _} =
      Board.upsert_comment(
        task,
        %{"id" => id, "user" => %{"login" => "sallaumen-agent"}, "body" => body},
        "sallaumen-agent"
      )
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

  test "events with no repository is empty", _ctx do
    assert Board.events(nil) == []
  end

  test "board with no repository is empty, not a crash", _ctx do
    assert {:ok, board} = Board.board(nil)
    assert board.repos == []
    assert board.merged == []
    assert board.running == []
  end

  test "an unknown slug is an error, not a crash", _ctx do
    assert Board.board("nobody/nothing") == :error
  end

  test "a blocked task lands in the blocked column", _ctx do
    {:ok, repo} = Board.add_repository("sallaumen", "arena-rogue")

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 901,
      title: "Blocked",
      state: "blocked"
    })
    |> Repo.insert!()

    assert {:ok, board} = Board.board("sallaumen/arena-rogue")
    assert Enum.any?(board.blocked, &(&1.number == 901))
    refute Enum.any?(board.queued, &(&1.number == 901))
  end
end

defmodule AgentBoard.BoardOverviewTest do
  @moduledoc "The rail's counts and the reconnect change count, from real rows."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.{Comment, PullRequest, Task}

  test "the rail counts running, waiting and failing work per repository" do
    {:ok, repo} = Board.add_repository("sallaumen", "attention")

    for {number, state} <- [{1, "running"}, {2, "ready"}, {3, "blocked"}] do
      insert_task(repo, number, state)
    end

    insert_merged(repo, 10, "failure")

    overview = Board.repo_overview()[repo.id]
    assert overview.running == 1
    assert overview.you == 1
    assert overview.halt == 1
    assert overview.unknown
  end

  test "a ready task linked to a merged PR no longer waits for a person" do
    {:ok, repo} = Board.add_repository("fixture", "resolved")
    linked = insert_task(repo, 2, "ready")
    _open = insert_task(repo, 3, "ready")
    pull = insert_merged(repo, 42, "success")

    %Comment{}
    |> Comment.changeset(%{
      task_id: linked.id,
      github_id: 100,
      author: "sallaumen-agent",
      kind: "agent",
      body: "Ready for review: https://github.com/fixture/resolved/pull/#{pull.number}"
    })
    |> Repo.insert!()

    {:ok, board} = Board.board("fixture/resolved")

    assert Enum.map(board.ready, & &1.number) == [3]
    assert board.task_counts.ready == 1
    assert Board.repo_overview()[repo.id].you == 1

    assert Board.reconcile_resolved_tasks(repo) == 1
    assert Repo.get(Task, linked.id).state == "done"
    assert Repo.get(Task, _open.id).state == "ready"
    assert Board.repo_overview()[repo.id].you == 1
  end

  test "a clean sync makes the repository known" do
    {:ok, repo} = Board.add_repository("sallaumen", "known")
    Board.log_event(repo.id, "sync", "sallaumen/known", %{"errors" => 0})

    refute Board.repo_overview()[repo.id].unknown
  end

  test "the sync snapshot keeps the last success apart from the failed attempt" do
    {:ok, repo} = Board.add_repository("sallaumen", "snapshot")
    Board.log_event(repo.id, "sync", "sallaumen/snapshot", %{"errors" => 0})
    Board.log_event(repo.id, "sync_error", "sallaumen/snapshot", %{"reason" => "offline"})

    snapshot = Board.sync_snapshot(repo)
    assert snapshot.last_attempt.kind == "sync_error"
    assert snapshot.last_success.kind == "sync"
  end

  test "the change count sees state changes, new tasks and new merges" do
    {:ok, repo} = Board.add_repository("sallaumen", "changes")
    task = insert_task(repo, 1, "ready")
    moved = %{task | state: "running"}
    fresh = insert_task(repo, 2, "queued")
    merged = insert_merged(repo, 3, "success")

    old = %{running: [], ready: [task], blocked: [], queued: [], merged: []}
    new = %{running: [moved], ready: [], blocked: [], queued: [fresh], merged: [merged]}

    assert Board.change_count(old, new) == 3
  end

  defp insert_task(repo, number, state) do
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

  defp insert_merged(repo, number, checks) do
    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: number,
      title: "PR #{number}",
      state: "merged",
      merged_at: DateTime.utc_now(),
      checks_state: checks
    })
    |> Repo.insert!()
  end
end

defmodule AgentBoard.BoardChangesTest do
  @moduledoc "The reconnect count uses stored timestamps, not a live process."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Repo}
  alias AgentBoard.Board.Task

  test "changes since a point count tasks, merges and comments" do
    {:ok, repo} = Board.add_repository("fixture", "changes-since")
    since = DateTime.add(DateTime.utc_now(), -60, :second)

    %Task{}
    |> Task.changeset(%{
      repository_id: repo.id,
      kind: "issue",
      number: 1,
      title: "New after the freeze",
      state: "queued",
      state_changed_at: DateTime.utc_now()
    })
    |> Repo.insert!()

    assert Board.changes_since(repo, since) == 1
    assert Board.changes_since(repo, DateTime.add(since, 60, :second)) == 0
  end
end
