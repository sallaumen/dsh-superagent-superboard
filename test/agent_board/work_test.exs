defmodule AgentBoard.WorkTest do
  @moduledoc "The reading lanes: order, freshness markers, duplicates and the digest."
  use AgentBoard.DataCase, async: true

  import Ecto.Query

  alias AgentBoard.{Board, Repo, Work}
  alias AgentBoard.Board.{Comment, PullRequest, Task}

  test "needs puts new items before old ones and follows the urgency order" do
    {:ok, repo} = Board.add_repository("fixture", "needs")
    now = ~U[2026-11-06 15:00:00Z]
    last_visit = DateTime.add(now, -3600, :second)

    old_review = task(repo, 1, "Old review", "ready", DateTime.add(now, -7200, :second))
    new_blocked = task(repo, 2, "New blocked", "blocked", DateTime.add(now, -60, :second))
    new_review = task(repo, 3, "New review", "ready", DateTime.add(now, -60, :second))
    _failure = merged(repo, 4, "Main red", "failure", DateTime.add(now, -60, :second))

    board = %{ready: [old_review, new_review], blocked: [new_blocked], question: [], running: []}

    needs = Work.needs(repo, board, now: now, last_visit: last_visit)

    # Merjed work is done; a red remote check is not a decision for the person.
    assert Enum.map(needs, & &1.title) == ["New blocked", "New review", "Old review"]
    assert Enum.map(needs, & &1.kind) == [:blocked, :review, :review]
    assert Enum.at(needs, 0).is_new
    refute Enum.at(needs, 2).is_new
    refute Enum.any?(needs, &(&1.kind == :cifail))
  end

  test "a review names its PR, links it and shows the CI it can see" do
    {:ok, repo} = Board.add_repository("fixture", "review-need")
    now = ~U[2026-11-06 15:00:00Z]
    review = task(repo, 27, "Pixel art", "ready", DateTime.add(now, -60, :second))
    pull = open_pull(repo, 28, "Replace geometric art", "failure")

    ticket = %{
      "numbers" => [27],
      "own_threads" => [28],
      "report" => "waiting",
      "report_summary" => "PR #28 remains ready for human review."
    }

    [need] =
      Work.needs(repo, %{ready: [review], blocked: [], question: []},
        now: now,
        tickets_by_number: %{27 => ticket},
        local_ci: %{}
      )

    assert need.kind == :review
    assert need.why =~ "PR #28 pronto para revisão"
    assert need.ci.note == "CI local ?"
    assert need.ci.title =~ "GitHub Actions falhou"
    assert need.ci.title =~ "sem evidência de CI local"
    assert Enum.any?(need.actions, &(&1[:url] == pull.url and &1.label == "Abrir PR #28"))
    assert Enum.any?(need.actions, &(&1[:task_id] == review.id))
  end

  test "a review with a local gate says the local gate passed" do
    {:ok, repo} = Board.add_repository("fixture", "review-local")
    now = ~U[2026-11-06 15:00:00Z]
    review = task(repo, 27, "Pixel art", "ready", DateTime.add(now, -60, :second))
    _pull = open_pull(repo, 28, "Replace geometric art", "failure")

    local = %{
      28 => %{
        state: :pass,
        detail: "mix precommit passed: 126 tests, 0 failures",
        remote_blocked: true,
        at: nil,
        scope: :pr,
        evidence_pr: nil
      }
    }

    [need] =
      Work.needs(repo, %{ready: [review], blocked: [], question: []},
        now: now,
        tickets_by_number: %{27 => %{"numbers" => [27], "own_threads" => [28]}},
        local_ci: local
      )

    assert need.ci.note == "CI local ok"
    assert need.ci.title =~ "billing"
    assert need.ci.title =~ "126 tests"
  end

  test "a review whose PR the board cannot find says so instead of guessing" do
    {:ok, repo} = Board.add_repository("fixture", "review-nopr")
    now = ~U[2026-11-06 15:00:00Z]
    review = task(repo, 27, "Pixel art", "ready", DateTime.add(now, -60, :second))

    [need] = Work.needs(repo, %{ready: [review], blocked: [], question: []}, now: now)

    assert need.why =~ "Pronto para revisão"
    assert need.why =~ "PR não identificado"
    assert need.ci == nil
    refute Enum.any?(need.actions, & &1[:url])
  end

  test "a question quotes the agent's question and a block states its reason" do
    {:ok, repo} = Board.add_repository("fixture", "needs-why")
    now = ~U[2026-11-06 15:00:00Z]
    asked = task(repo, 30, "Which API", "question", DateTime.add(now, -60, :second))
    silent = task(repo, 31, "Silent", "question", DateTime.add(now, -60, :second))
    blocked = task(repo, 32, "Stuck", "blocked", DateTime.add(now, -60, :second))
    quiet_block = task(repo, 33, "Quiet", "blocked", DateTime.add(now, -60, :second))

    comment(asked, "agent", "Devo usar a API v2 ou manter a v1?")
    comment(silent, "agent", "Entendido: começo pelo mapa.")

    tickets = %{
      32 => %{"numbers" => [32], "report_summary" => "Cannot reach the registry."},
      33 => %{"numbers" => [33]}
    }

    needs =
      Work.needs(repo, %{ready: [], blocked: [blocked, quiet_block], question: [asked, silent]},
        now: now,
        tickets_by_number: tickets
      )

    whys = Map.new(needs, &{&1.number, &1.why})

    assert whys[30] =~ "O agente perguntou:** Devo usar a API v2 ou manter a v1?"
    assert whys[31] =~ "O agente espera uma resposta sua"
    refute whys[31] =~ "perguntou"
    assert whys[32] =~ "Bloqueado:** Cannot reach the registry."
    assert whys[33] =~ "Bloqueado"
    assert whys[33] =~ "sem motivo no relatório"
  end

  test "queue keeps arrival order and warns about a merged duplicate" do
    {:ok, repo} = Board.add_repository("fixture", "queue")
    now = ~U[2026-11-06 15:00:00Z]

    merged(repo, 24, "Spread deterministic seed spawns across each arena edge", "success", now)

    later =
      task(repo, 22, "Spread deterministic seed spawns across each arena edge", "queued", now)

    earlier = task(repo, 20, "Unrelated work", "queued", DateTime.add(now, -3600, :second))

    queue = Work.queue(repo, %{}, now: now)

    assert Enum.map(queue.items, & &1.id) == [earlier.id, later.id]
    assert Enum.at(queue.items, 1).note == "Parece repetir #24, já mesclado"
    assert queue.counts.dupes == 1
  end

  test "the merge log groups the last seven days and counts every PR" do
    {:ok, repo} = Board.add_repository("fixture", "log")
    today = ~U[2026-11-06 15:00:00Z]

    merged(repo, 1, "Today", "success", today)
    merged(repo, 2, "Yesterday", "failure", DateTime.add(today, -86_400, :second))
    merged(repo, 3, "Old", "success", DateTime.add(today, -8 * 86_400, :second))

    local = %{
      2 => %{
        state: :pass,
        detail: "mix precommit passed (testes, formato, Credo)",
        remote_blocked: true
      }
    }

    log = Work.merge_log(repo, now: today, tz_offset: 0, local_ci: local)

    assert log.total == 2
    assert List.last(log.days).n == 1
    assert Enum.find(log.days, &(&1.date == Date.add(Date.utc_today(), -1))).n == 1
    assert Enum.map(log.groups, & &1.label) == ["Hoje", "Ontem, 5 nov"]
    assert hd(log.groups).items |> hd() |> Map.fetch!(:ci) == "pass"

    yesterday = Enum.find(log.groups, &(&1.label == "Ontem, 5 nov"))
    item = hd(yesterday.items)
    assert item.ci == "pass"
    assert item.ciNote == "CI local ok"
    assert item.ciTitle =~ "CI local passou"
    assert item.ciTitle =~ "billing"
  end

  test "a red remote check without local evidence is quiet, not a red day" do
    {:ok, repo} = Board.add_repository("fixture", "remote-only")
    now = ~U[2026-11-06 15:00:00Z]
    merged(repo, 9, "Remote only", "failure", now)

    log = Work.merge_log(repo, now: now, tz_offset: 0)
    item = hd(hd(log.groups).items)

    assert item.ci == "unknown"
    assert item.ciNote == "CI local ?"
    assert item.ciTitle =~ "sem evidência de CI local"
    assert hd(log.days).fail == 0
  end

  test "the digest counts what changed since the visit, not the whole board" do
    {:ok, repo} = Board.add_repository("fixture", "digest")
    now = ~U[2026-11-06 15:00:00Z]
    last_visit = DateTime.add(now, -3600, :second)

    merged(repo, 1, "Merged since", "failure", DateTime.add(now, -60, :second))
    task(repo, 2, "Queued now", "queued", now)
    task(repo, 3, "Was already here", "queued", DateTime.add(now, -7200, :second))

    board = %{running: [], question: [], ready: [], blocked: [], task_counts: %{queued: 2}}
    digest = Work.digest(repo, board, now: now, last_visit: last_visit, tz_offset: 0)

    text = Enum.map_join(digest.segments, "", & &1.text)
    assert text =~ "mesclou 1 PR"
    refute text =~ "CI falhando"
    assert text =~ "1 nova na fila"
    refute text =~ "2 novas"
  end

  test "a first visit never claims a change time it does not have" do
    {:ok, repo} = Board.add_repository("fixture", "first")
    now = ~U[2026-11-06 15:00:00Z]
    task(repo, 2, "Queued now", "queued", now)

    board = %{running: [], question: [], ready: [], blocked: [], task_counts: %{queued: 1}}
    digest = Work.digest(repo, board, now: now, last_visit: nil, tz_offset: 0)

    assert digest.prefix == "Primeira visita: "
    assert Enum.map_join(digest.segments, "", & &1.text) =~ "1 na fila"
  end

  defp task(repo, number, title, state, at) do
    task =
      %Task{}
      |> Task.changeset(%{
        repository_id: repo.id,
        kind: "issue",
        number: number,
        title: title,
        state: state,
        state_changed_at: at
      })
      |> Repo.insert!()

    # Ecto always writes the current inserted_at; the lane's arrival order is
    # tested by setting the stored time explicitly.
    Repo.update_all(from(t in Task, where: t.id == ^task.id), set: [inserted_at: at])
    %{task | inserted_at: at}
  end

  defp open_pull(repo, number, title, checks) do
    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: number,
      title: title,
      state: "open",
      opened_at: ~U[2026-11-06 14:00:00Z],
      checks_state: checks,
      checks_failed: if(checks == "failure", do: "gates", else: nil),
      url: "https://github.com/fixture/repo/pull/#{number}"
    })
    |> Repo.insert!()
  end

  defp comment(task, kind, body) do
    %Comment{}
    |> Comment.changeset(%{
      task_id: task.id,
      github_id: System.unique_integer([:positive]),
      author: if(kind == "agent", do: "sallaumen-agent", else: "sallaumen"),
      body: body,
      kind: kind
    })
    |> Repo.insert!()
  end

  defp merged(repo, number, title, checks, at) do
    %PullRequest{}
    |> PullRequest.changeset(%{
      repository_id: repo.id,
      number: number,
      title: title,
      state: "merged",
      merged_at: at,
      checks_state: checks,
      checks_failed: if(checks == "failure", do: "gates", else: nil),
      url: "https://github.com/fixture/repo/pull/#{number}"
    })
    |> Repo.insert!()
  end
end

defmodule AgentBoard.WorkFrozenTest do
  @moduledoc "The frozen digest never claims a change it cannot see."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Work}

  test "without a successful sync the digest says it does not know" do
    {:ok, repo} = Board.add_repository("fixture", "frozen-digest")
    now = ~U[2026-11-06 15:00:00Z]
    board = %{running: [], question: [], ready: [], blocked: [], task_counts: %{queued: 0}}

    digest =
      Work.digest(repo, board,
        now: now,
        last_visit: DateTime.add(now, -3600, :second),
        tz_offset: 0,
        frozen: true,
        frozen_at: nil
      )

    assert digest.prefix == "Sem uma sincronia concluída, "
    assert Enum.map_join(digest.segments, "", & &1.text) == "não sabemos o que mudou"
    assert digest.suffix == "."
  end
end
