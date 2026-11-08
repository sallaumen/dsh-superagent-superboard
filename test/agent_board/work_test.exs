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

  test "a question quotes the workpad's Pergunta, not the comment's first line" do
    {:ok, repo} = Board.add_repository("fixture", "workpad-question")
    now = ~U[2026-11-06 15:00:00Z]
    question = task(repo, 31, "Boss fight", "question", DateTime.add(now, -60, :second))

    comment(question, "agent", """
    This is by an automated agent, not a human.

    ## Relatório do agente

    ### Plano
    Trocar a arena.

    ### Pergunta
    Devo manter o boss na arena ou tirar

    ### Bloqueio
    """)

    [need] = Work.needs(repo, %{ready: [], blocked: [], question: [question]}, now: now)

    assert need.why == "**O agente perguntou:** Devo manter o boss na arena ou tirar"
  end

  test "a block quotes the workpad's Bloqueio before the report" do
    {:ok, repo} = Board.add_repository("fixture", "workpad-block")
    now = ~U[2026-11-06 15:00:00Z]
    blocked = task(repo, 32, "Registry", "blocked", DateTime.add(now, -60, :second))

    comment(blocked, "agent", """
    ## Relatório do agente
    ### Bloqueio
    Sem acesso ao registry npm (403).
    """)

    ticket = %{"numbers" => [32], "report" => "waiting", "report_summary" => "Waiting."}

    [need] =
      Work.needs(repo, %{ready: [], blocked: [blocked], question: []},
        now: now,
        tickets_by_number: %{32 => ticket}
      )

    assert need.why == "**Bloqueado:** Sem acesso ao registry npm (403)."
  end

  test "a review whose gate ran on another commit shows an unknown local CI" do
    {:ok, repo} = Board.add_repository("fixture", "review-stale")
    now = ~U[2026-11-06 15:00:00Z]
    review = task(repo, 27, "Pixel art", "ready", DateTime.add(now, -60, :second))
    _pull = open_pull(repo, 28, "Replace geometric art", "failure")

    local = %{
      28 => %{
        state: :stale,
        detail:
          "mix precommit: passou em 44653e8, mas o head do PR é 9f1c2ab: o gate não cobre o commit atual.",
        remote_blocked: false,
        at: nil,
        scope: :workpad,
        evidence_pr: nil,
        sha: "44653e8",
        head_sha: "9f1c2ab0000000000000000000000000000000000"
      }
    }

    [need] =
      Work.needs(repo, %{ready: [review], blocked: [], question: []},
        now: now,
        tickets_by_number: %{27 => %{"numbers" => [27], "own_threads" => [28]}},
        local_ci: local
      )

    assert need.ci.state == "unknown"
    assert need.ci.note == "CI local ?"
    assert need.ci.title =~ "head do PR é 9f1c2ab"
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

  describe "agent failures" do
    @transport "LlmError: DeepSeek Messages transport failed"

    defp failed_ticket(number, summary, retried) do
      previous =
        for i <- 1..retried//1 do
          %{
            "id" => "a#{i}",
            "state" => "ended",
            "report" => %{"state" => "failed"},
            "endedReason" => "retried"
          }
        end

      AgentBoard.AgentState.normalize(%{
        "id" => "t#{number}",
        "mandate" => %{"basis" => %{"scope" => %{"number" => number}}},
        "assignments" =>
          previous ++
            [
              %{
                "id" => "latest-#{number}",
                "state" => "running",
                "report" => %{
                  "state" => "failed",
                  "summary" => summary,
                  "at" => "2026-11-07T17:10:00Z"
                }
              }
            ]
      })
    end

    test "a block says what failed and what is left to the owner" do
      {:ok, repo} = Board.add_repository("fixture", "failure-why")
      now = ~U[2026-11-07 18:00:00Z]
      out = task(repo, 60, "Out of retries", "blocked", DateTime.add(now, -60, :second))
      person = task(repo, 61, "Needs a person", "blocked", DateTime.add(now, -60, :second))

      tickets = %{
        60 => failed_ticket(60, @transport, 3),
        61 => failed_ticket(61, "Tests failed: 3 failures", 0)
      }

      needs =
        Work.needs(repo, %{ready: [], blocked: [out, person], question: []},
          now: now,
          tickets_by_number: tickets
        )

      whys = Map.new(needs, &{&1.number, &1.why})

      assert whys[60] ==
               "**Falha de rede ao chamar o modelo.** As 3 tentativas automáticas falharam; " <>
                 "tente de novo quando a rede voltar."

      assert whys[61] =~
               "Não parece falha de rede: leia o erro no detalhe antes de tentar de novo."
    end

    test "a retrying task is a row in Agora with its next attempt, not an item for the owner" do
      {:ok, repo} = Board.add_repository("fixture", "failure-retrying")
      now = ~U[2026-11-07 17:10:30Z]
      retrying = task(repo, 62, "Retrying", "retrying", DateTime.add(now, -30, :second))
      board = %{ready: [], blocked: [], question: [], retrying: [retrying]}
      tickets = %{62 => failed_ticket(62, @transport, 0)}

      assert Work.needs(repo, board, now: now, tickets_by_number: tickets) == []

      assert [%{number: 62, line: line}] =
               Work.retrying(board, now: now, tz_offset: 180, tickets_by_number: tickets)

      assert line ==
               "**Falha de rede ao chamar o modelo.** Nova tentativa automática às 14:11 (1 de 3)."
    end

    test "with the orchestrator down, blocks and silences become one item" do
      {:ok, repo} = Board.add_repository("fixture", "agent-down")
      now = ~U[2026-11-07 18:00:00Z]
      blocked = task(repo, 63, "Blocked", "blocked", DateTime.add(now, -60, :second))
      review = task(repo, 64, "Review", "ready", DateTime.add(now, -60, :second))
      retrying = task(repo, 65, "Retrying", "retrying", DateTime.add(now, -60, :second))
      board = %{ready: [review], blocked: [blocked], question: [], retrying: [retrying]}

      assert [down, %{number: 64, kind: :review}] =
               Work.needs(repo, board, now: now, agent: :down)

      assert %{kind: :agent_down, title: "Agente fora do ar", number: nil, waiting: 2} = down

      assert down.why ==
               "**O orquestrador não responde.** 2 tarefas esperam ele voltar; as falhas de rede voltam a ser tentadas sozinhas."

      assert [%{label: "Religar o agente", restart_agent: true}] = down.actions

      assert Enum.map(Work.needs(repo, board, now: now, agent: :up), & &1.kind) == [
               :blocked,
               :review
             ]
    end
  end

  test "a running task that went silent needs the owner; a fresh one is quiet" do
    {:ok, repo} = Board.add_repository("fixture", "silence")
    now = ~U[2026-11-07 12:00:00Z]
    quiet = task(repo, 50, "Silent run", "running", DateTime.add(now, -3600, :second))
    busy = task(repo, 51, "Busy run", "running", DateTime.add(now, -3600, :second))

    silences = %{
      50 => %{at: ~U[2026-11-07 11:30:00Z], source: :report, seconds: 1800},
      51 => %{at: ~U[2026-11-07 11:58:00Z], source: :worktree, seconds: 120}
    }

    [need] =
      Work.needs(repo, %{ready: [], blocked: [], question: [], running: [quiet, busy]},
        now: now,
        last_visit: DateTime.add(now, -1200, :second),
        silences: silences,
        stall_after: 900
      )

    assert need.kind == :stalled
    assert need.number == 50
    assert need.why =~ "**Sem sinal há 30 min.** O último relatório do agente foi às 11:30"
    # it crossed the threshold at 11:45: that is its age, and it is newer than the 11:40 visit
    assert need.age_seconds == 900
    assert need.is_new
    assert need.actions == [%{label: "Ver detalhe", task_id: quiet.id}]
  end

  test "a silence says what the board saw last" do
    {:ok, repo} = Board.add_repository("fixture", "silence-why")
    now = ~U[2026-11-07 12:00:00Z]
    edited = task(repo, 52, "Edited", "running", now)
    started = task(repo, 53, "Started", "running", now)

    silences = %{
      52 => %{at: ~U[2026-11-07 11:00:00Z], source: :worktree, seconds: 3600},
      53 => %{at: ~U[2026-11-07 10:00:00Z], source: :start, seconds: 7200}
    }

    whys =
      Work.needs(repo, %{ready: [], blocked: [], question: [], running: [edited, started]},
        now: now,
        silences: silences,
        stall_after: 900,
        tz_offset: 180
      )
      |> Map.new(&{&1.number, &1.why})

    assert whys[52] =~ "A última mudança no worktree foi às 08:00; nenhum relatório depois."
    assert whys[53] =~ "Começou às 07:00 e não deu sinal desde então"
  end

  test "a silence ranks after a block and before a review" do
    {:ok, repo} = Board.add_repository("fixture", "silence-rank")
    now = ~U[2026-11-07 12:00:00Z]
    at = DateTime.add(now, -60, :second)
    review = task(repo, 60, "Review", "ready", at)
    quiet = task(repo, 61, "Quiet", "running", at)
    blocked = task(repo, 62, "Blocked", "blocked", at)

    needs =
      Work.needs(repo, %{ready: [review], blocked: [blocked], question: [], running: [quiet]},
        now: now,
        silences: %{61 => %{at: ~U[2026-11-07 11:00:00Z], source: :report, seconds: 3600}},
        stall_after: 900
      )

    assert Enum.map(needs, & &1.kind) == [:blocked, :stalled, :review]
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
    assert Enum.find(log.days, &(&1.date == Date.add(DateTime.to_date(today), -1))).n == 1
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
