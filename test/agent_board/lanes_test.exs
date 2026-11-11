defmodule AgentBoard.LanesTest do
  @moduledoc "The reading lanes: order, freshness markers, duplicates and the digest."
  use AgentBoard.DataCase, async: true

  import Ecto.Query

  alias AgentBoard.{Board, Lanes, Repo}
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

    needs = Lanes.needs(repo, board, now: now, last_visit: last_visit)

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
      Lanes.needs(repo, %{ready: [review], blocked: [], question: []},
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
      Lanes.needs(repo, %{ready: [review], blocked: [], question: []},
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

    [need] = Lanes.needs(repo, %{ready: [], blocked: [], question: [question]}, now: now)

    assert need.why == "**O agente perguntou:** Devo manter o boss na arena ou tirar"
  end

  test "a question quotes the agent's words, not the runner's hidden marker" do
    {:ok, repo} = Board.add_repository("fixture", "marker-question")
    now = ~U[2026-11-06 15:00:00Z]
    question = task(repo, 32, "Which API", "question", DateTime.add(now, -60, :second))

    comment(question, "agent", "<!-- dsh-superagent:x -->\nSim, devo usar a API v2?")

    [need] = Lanes.needs(repo, %{ready: [], blocked: [], question: [question]}, now: now)

    assert need.why == "**O agente perguntou:** Sim, devo usar a API v2?"
  end

  describe "the next moment a running task needs attention" do
    @now ~U[2026-11-10 12:00:00.000Z]

    test "is the nearest future limit or silence, in milliseconds" do
      started = DateTime.add(@now, -10 * 60, :second)
      small = %{number: 1, size: "S", state_changed_at: started, started_at: started}
      quiet = %{number: 2, size: "L", state_changed_at: started, started_at: started}
      silences = %{2 => %{at: DateTime.add(@now, -60, :second)}}

      assert Lanes.next_attention_in([small, quiet], silences, 121, @now) == 61_000
      assert Lanes.next_attention_in([small], %{}, 121, @now) == 10 * 60 * 1000
    end

    test "a limit under a second away still counts, and a passed one never does" do
      soon = DateTime.add(@now, -(20 * 60) + 1, :second) |> DateTime.add(-500, :millisecond)
      passed = DateTime.add(@now, -30 * 60, :second)

      assert Lanes.next_attention_in(
               [%{number: 1, size: "S", state_changed_at: soon, started_at: soon}],
               %{},
               60,
               @now
             ) == 500

      assert Lanes.next_attention_in(
               [%{number: 1, size: "S", state_changed_at: passed, started_at: passed}],
               %{},
               60,
               @now
             ) == nil
    end
  end

  describe "a run past the time its size allows" do
    @now ~U[2026-11-10 15:00:00Z]

    defp running(repo, number, size, minutes) do
      task = task(repo, number, "Run #{number}", "running", DateTime.add(@now, -minutes * 60))
      %{task | size: size}
    end

    defp slow(repo, tasks, opts \\ []) do
      Lanes.needs(repo, %{running: tasks}, Keyword.merge([now: @now], opts))
    end

    test "is a heads-up from the limit on: small 20, medium 40, large and unsized 60 min" do
      {:ok, repo} = Board.add_repository("fixture", "slow-limits")

      on_time = [
        running(repo, 1, "S", 19),
        running(repo, 2, "M", 39),
        running(repo, 3, "L", 59),
        running(repo, 4, nil, 59)
      ]

      assert slow(repo, on_time) == []

      late = [
        running(repo, 5, "S", 20),
        running(repo, 6, "M", 40),
        running(repo, 7, "L", 60),
        running(repo, 8, nil, 60)
      ]

      needs = slow(repo, late)
      assert needs |> Enum.map(& &1.number) |> Enum.sort() == [5, 6, 7, 8]

      assert Enum.all?(needs, &(&1.kind == :slow and &1.age_seconds == 0))
      assert Enum.map(needs, &hd(&1.actions).label) |> Enum.uniq() == ["Ver detalhe"]
      assert Lanes.slow_after("S") == 20 * 60
      assert Lanes.slow_after(nil) == Lanes.slow_after("L")
    end

    test "says since when, the limit that made it one and the last signal it has" do
      {:ok, repo} = Board.add_repository("fixture", "slow-why")
      small = running(repo, 9, "S", 34)

      assert [%{why: why}] = slow(repo, [small])

      assert why ==
               "**Trabalhando desde 14:26 (há 34 min).** Uma tarefa pequena é sinalizada depois de 20 min."

      silences = %{9 => %{at: DateTime.add(@now, -120), source: :worktree, seconds: 120}}

      assert [%{why: why, age_seconds: 840}] = slow(repo, [small], silences: silences)
      assert why =~ "sinalizada depois de 20 min. Último sinal há 2 min."

      assert [%{why: unsized}] = slow(repo, [running(repo, 10, nil, 61)])
      assert unsized =~ "Uma tarefa sem tamanho é sinalizada depois de 60 min."
    end

    test "gives way to the silence: one task, one reason to look" do
      {:ok, repo} = Board.add_repository("fixture", "slow-silent")
      small = running(repo, 11, "S", 34)
      silences = %{11 => %{at: DateTime.add(@now, -1200), source: :report, seconds: 1200}}

      assert [%{kind: :stalled, number: 11}] =
               slow(repo, [small], silences: silences, stall_after: 900)
    end

    test "comes after everything that waits for the owner, and waits with the agent down" do
      {:ok, repo} = Board.add_repository("fixture", "slow-order")
      small = running(repo, 12, "S", 34)
      question = task(repo, 13, "Question", "question", DateTime.add(@now, -3600))
      board = %{running: [small], question: [question], blocked: [], ready: []}

      assert Enum.map(Lanes.needs(repo, board, now: @now), & &1.kind) == [:question, :slow]

      assert [%{kind: :agent_down, waiting: 1}, %{kind: :question}] =
               Lanes.needs(repo, board, now: @now, agent: :down)
    end

    test "a silence that began with the owner's answer says so" do
      {:ok, repo} = Board.add_repository("fixture", "silent-after-answer")
      run = running(repo, 14, "L", 30)
      silences = %{14 => %{at: DateTime.add(@now, -1200), source: :answer, seconds: 1200}}

      assert [%{kind: :stalled, why: why}] =
               slow(repo, [run], silences: silences, stall_after: 900)

      assert why ==
               "**Sem sinal há 20 min.** O agente leu sua resposta às 14:40; nenhum sinal desde então."
    end
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
      Lanes.needs(repo, %{ready: [], blocked: [blocked], question: []},
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
      Lanes.needs(repo, %{ready: [review], blocked: [], question: []},
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

    [need] = Lanes.needs(repo, %{ready: [review], blocked: [], question: []}, now: now)

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
      Lanes.needs(repo, %{ready: [], blocked: [blocked, quiet_block], question: [asked, silent]},
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
        Lanes.needs(repo, %{ready: [], blocked: [out, person], question: []},
          now: now,
          tickets_by_number: tickets
        )

      whys = Map.new(needs, &{&1.number, &1.why})

      assert whys[60] ==
               "**Falha de rede ao chamar o modelo.** As 3 tentativas automáticas falharam; " <>
                 "tente de novo quando a rede voltar."

      assert whys[61] =~
               "Não parece falha de rede: leia o erro no detalhe antes de tentar de novo."

      # the attempt is asked for on the card, without opening the detail
      retry = %{ticket_id: "t61", repository_id: repo.id, number: 61}

      assert [%{label: "Tentar de novo", retry: ^retry}, %{label: "Ver detalhe"}] =
               Enum.find(needs, &(&1.number == 61)).actions
    end

    test "a block with no ticket has only the detail" do
      {:ok, repo} = Board.add_repository("fixture", "failure-no-ticket")
      blocked = task(repo, 66, "Blocked", "blocked", ~U[2026-11-07 17:00:00Z])

      assert [%{actions: [%{label: "Ver detalhe"}]}] =
               Lanes.needs(repo, %{blocked: [blocked]}, now: ~U[2026-11-07 18:00:00Z])
    end

    test "a retrying task is a row in Agora with its next attempt, not an item for the owner" do
      {:ok, repo} = Board.add_repository("fixture", "failure-retrying")
      now = ~U[2026-11-07 17:10:30Z]
      retrying = task(repo, 62, "Retrying", "retrying", DateTime.add(now, -30, :second))
      board = %{ready: [], blocked: [], question: [], retrying: [retrying]}
      tickets = %{62 => failed_ticket(62, @transport, 0)}

      assert Lanes.needs(repo, board, now: now, tickets_by_number: tickets) == []

      assert [%{number: 62, line: line}] =
               Lanes.retrying(board, now: now, tz_offset: 180, tickets_by_number: tickets)

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
               Lanes.needs(repo, board, now: now, agent: :down)

      assert %{
               kind: :agent_down,
               title: "Nenhuma tarefa nova começa até ele voltar",
               number: nil,
               waiting: 2
             } = down

      assert down.why ==
               "**O orquestrador não responde.** 2 tarefas esperam ele voltar; as falhas de rede voltam a ser tentadas sozinhas."

      assert [%{label: "Religar o agente", restart_agent: true}] = down.actions

      assert Enum.map(Lanes.needs(repo, board, now: now, agent: :up), & &1.kind) == [
               :blocked,
               :review
             ]
    end
  end

  test "the English board reads the lanes in English" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    {:ok, repo} = Board.add_repository("fixture", "english")
    now = ~U[2026-11-06 15:00:00Z]
    blocked = task(repo, 63, "Blocked", "blocked", DateTime.add(now, -60, :second))
    review = task(repo, 64, "Review", "ready", DateTime.add(now, -60, :second))
    merged(repo, 1, "Merged since", "failure", DateTime.add(now, -60, :second))
    board = %{running: [], ready: [review], blocked: [blocked], question: [], retrying: []}

    assert [down, %{kind: :review, actions: [%{label: "Review"}]}] =
             Lanes.needs(repo, board, now: now, agent: :down)

    assert down.title == "No new task starts until it is back"

    assert down.why ==
             "**The orchestrator is not responding.** 1 task waits for it to come back; network failures are retried on their own."

    assert [%{label: "Restart the agent"}] = down.actions

    digest =
      Lanes.digest(repo, board,
        now: now,
        last_visit: DateTime.add(now, -3600, :second),
        tz_offset: 0
      )

    assert digest.prefix == "Since today at 14:00 "

    assert Enum.map_join(digest.segments, "", & &1.text) ==
             "the agent merged 1 PR and #63 is still blocked"

    log = Lanes.merge_log(repo, now: now, tz_offset: 0)
    assert [%{label: "Today", items: [item]}] = log.groups
    assert item.ciNote == "Local CI unknown"
    assert item.review == "no review"
  end

  test "a running task that went silent needs the owner; a fresh one is quiet" do
    {:ok, repo} = Board.add_repository("fixture", "silence")
    now = ~U[2026-11-07 12:00:00Z]
    quiet = task(repo, 50, "Silent run", "running", DateTime.add(now, -3600, :second))
    # under the hour a task without a size is allowed: a busy run is no item
    busy = task(repo, 51, "Busy run", "running", DateTime.add(now, -3540, :second))

    silences = %{
      50 => %{at: ~U[2026-11-07 11:30:00Z], source: :report, seconds: 1800},
      51 => %{at: ~U[2026-11-07 11:58:00Z], source: :worktree, seconds: 120}
    }

    [need] =
      Lanes.needs(repo, %{ready: [], blocked: [], question: [], running: [quiet, busy]},
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
      Lanes.needs(repo, %{ready: [], blocked: [], question: [], running: [edited, started]},
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
      Lanes.needs(repo, %{ready: [review], blocked: [blocked], question: [], running: [quiet]},
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

    queue = Lanes.queue(repo, now: now)

    assert Enum.map(queue.items, & &1.id) == [earlier.id, later.id]
    assert Enum.at(queue.items, 1).note == "Parece repetir #24, já mesclado"
    assert queue.counts.dupes == 1
  end

  test "a linked blocker comes first and names the task it unblocks" do
    {:ok, repo} = Board.add_repository("fixture", "queue-blocker")
    now = ~U[2026-11-06 15:00:00Z]

    blocked = task(repo, 20, "Blocked work", "queued", DateTime.add(now, -3600, :second))
    normal = task(repo, 21, "Normal work", "queued", DateTime.add(now, -3600, :second))

    blocker =
      task(repo, 22, "Desbloquear #20", "queued", now)
      |> Task.changeset(%{blocker_for_task_id: blocked.id})
      |> Repo.update!()

    queue = Lanes.queue(repo, now: now)

    assert Enum.map(queue.items, & &1.id) == [blocker.id, blocked.id, normal.id]
    assert hd(queue.items).sub == "desbloqueia #20"
    refute Enum.at(queue.items, 1).sub
  end

  describe "a task the board called and no ticket answered" do
    setup do
      {:ok, repo} = Board.add_repository("fixture", "unanswered")
      %{repo: repo, now: ~U[2026-11-10 11:27:00Z]}
    end

    defp called(repo, number, at, attrs \\ %{}) do
      task = task(repo, number, "Called #{number}", "queued", at)
      attrs = Map.merge(%{released_at: at, executor: "dsh"}, attrs)
      Repo.update_all(from(t in Task, where: t.id == ^task.id), set: Map.to_list(attrs))
      Map.merge(task, attrs)
    end

    test "needs the owner, says since when and offers to call again", %{repo: repo, now: now} do
      stuck = called(repo, 182, ~U[2026-11-09 20:47:31Z])

      [need] =
        Lanes.needs(repo, %{queued: [stuck]}, now: now, stall_after: 900, tz_offset: 180)

      assert need.kind == :unanswered
      assert need.number == 182
      assert need.why =~ "**Chamado há 14 h e o agente não começou.**"
      assert need.why =~ "ontem às 17:47"
      # it became the owner's when the call was 15 minutes old
      assert need.age_seconds == 14 * 3600 + 39 * 60 + 29 - 900

      assert [%{label: "Chamar de novo", release: phrase}, %{label: "Ver detalhe"}] =
               need.actions

      assert phrase == AgentBoard.Actions.phrase(:release_task, %{task: stuck, repository: repo})
    end

    test "the queue says who holds a called task before it starts", %{repo: repo, now: now} do
      recent = DateTime.add(now, -600, :second)
      first = called(repo, 1, recent)
      called(repo, 2, recent)
      called(repo, 3, recent)
      called(repo, 4, recent, %{executor: "claude", released_at: nil})
      called(repo, 5, recent)
      split = called(repo, 6, recent)
      Repo.update_all(from(t in Task, where: t.id == ^split.id), set: [origin_task_id: first.id])
      called(repo, 7, recent)

      queue =
        Lanes.queue(repo,
          now: now,
          stall_after: 900,
          tickets_by_number: %{
            # the wait is the assignment's, not the call's
            2 => %{
              "numbers" => [2],
              "assignments" => [%{"created_at" => DateTime.add(now, -300, :second)}]
            },
            5 => %{"numbers" => [5], "assignment" => "pending"},
            7 => %{"numbers" => [7], "stopped" => true},
            3 => %{"numbers" => [3], "started_at" => recent, "ended_at" => now}
          }
        )

      assert Map.new(queue.items, &{&1.number, &1.sub}) == %{
               1 => "chamado há 10 min, aguardando o agente",
               2 => "na fila do agente há 5 min",
               3 => nil,
               4 => nil,
               5 => "na fila do agente",
               6 => "dividido de #1 · chamado há 10 min, aguardando o agente",
               7 => nil
             }

      # a call line is not a split
      assert queue.counts.split == 1

      assert Enum.all?(queue.items, &is_nil(&1.stuck))
    end

    test "is only a task with no ticket, called long enough ago", %{repo: repo, now: now} do
      taken = called(repo, 1, ~U[2026-11-09 20:47:31Z])
      fresh = called(repo, 2, DateTime.add(now, -600, :second))
      held = called(repo, 3, ~U[2026-11-09 20:47:31Z], %{held: true, released_at: nil})
      other = called(repo, 4, ~U[2026-11-09 20:47:31Z], %{executor: "claude", released_at: nil})
      created = called(repo, 5, ~U[2026-11-09 20:47:31Z], %{released_at: nil})

      needs =
        Lanes.needs(repo, %{queued: [taken, fresh, held, other, created]},
          now: now,
          stall_after: 900,
          tickets_by_number: %{1 => %{"numbers" => [1], "assignment" => "pending"}}
        )

      # an issue opened with the mention was called when it was created
      assert Enum.map(needs, & &1.number) == [5]
    end

    test "a call the board could not finish is the owner's within a minute",
         %{repo: repo, now: now} do
      at = DateTime.add(now, -120, :second)
      failed = called(repo, 190, at, %{held: true})
      called(repo, 191, DateTime.add(now, -20, :second), %{held: true})

      [need] =
        Lanes.needs(repo, %{queued: [failed]}, now: now, stall_after: 900, tz_offset: 180)

      assert need.kind == :unanswered

      assert need.why ==
               "**A chamada ao agente não foi concluída.** " <>
                 "O board tentou hoje às 08:25 e não tenta de novo sozinho."

      assert need.age_seconds == 120

      assert [%{label: "Chamar de novo", release: _phrase}, %{label: "Ver detalhe"}] =
               need.actions

      queue = Lanes.queue(repo, now: now, stall_after: 900)

      # the comment may still be on its way
      assert %{190 => "a chamada ao agente não foi concluída", 191 => nil} =
               Map.new(queue.items, &{&1.number, &1.stuck})

      assert %{190 => nil, 191 => "espera as dependências"} =
               Map.new(queue.items, &{&1.number, &1.sub})
    end

    test "waits with everything else when the agent is down", %{repo: repo, now: now} do
      stuck = called(repo, 182, ~U[2026-11-09 20:47:31Z])

      assert [%{kind: :agent_down, waiting: 1}] =
               Lanes.needs(repo, %{queued: [stuck]}, now: now, stall_after: 900, agent: :down)
    end

    test "the queue says it, and a held task names what it waits for", %{repo: repo, now: now} do
      stuck = called(repo, 182, ~U[2026-11-09 20:47:31Z])
      held = called(repo, 184, ~U[2026-11-09 20:36:11Z], %{held: true, released_at: nil})
      done = task(repo, 183, "Done", "done", now)
      at = DateTime.truncate(now, :second)

      Repo.insert_all(AgentBoard.Board.TaskDependency, [
        %{task_id: held.id, blocked_by_task_id: stuck.id, inserted_at: at, updated_at: at},
        %{task_id: held.id, blocked_by_task_id: done.id, inserted_at: at, updated_at: at}
      ])

      queue = Lanes.queue(repo, now: now, stall_after: 900)

      assert %{184 => "espera #182", 182 => nil} = Map.new(queue.items, &{&1.number, &1.sub})

      assert %{182 => "chamado há 14 h, o agente não começou", 184 => nil} =
               Map.new(queue.items, &{&1.number, &1.stuck})

      taken = Lanes.queue(repo, now: now, stall_after: 900, tickets_by_number: %{182 => %{}})
      assert Enum.all?(taken.items, &is_nil(&1.stuck))
    end
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

    log = Lanes.merge_log(repo, now: today, tz_offset: 0, local_ci: local)

    assert log.total == 2
    assert List.last(log.days).n == 1
    assert Enum.take(log.days, -2) |> Enum.map(& &1.label) == ["Ontem, 5 nov", "Hoje"]
    assert Enum.find(log.days, &(&1.date == Date.add(DateTime.to_date(today), -1))).n == 1
    assert Enum.map(log.groups, & &1.label) == ["Hoje", "Ontem, 5 nov"]
    assert Enum.map(log.groups, & &1.date) == [~D[2026-11-06], ~D[2026-11-05]]
    assert hd(log.groups).items |> hd() |> Map.fetch!(:ci) == "pass"

    yesterday = Enum.find(log.groups, &(&1.label == "Ontem, 5 nov"))
    item = hd(yesterday.items)
    assert item.ci == "pass"
    assert item.ciNote == "CI local ok"
    assert item.ciTitle =~ "CI local passou"
    assert item.ciTitle =~ "billing"
  end

  test "a day keeps three merges and offers five more to a wide window" do
    {:ok, repo} = Board.add_repository("fixture", "wide-day")
    now = ~U[2026-11-06 15:00:00Z]
    for n <- 1..10, do: merged(repo, n, "PR #{n}", "success", DateTime.add(now, -n, :minute))

    group = hd(Lanes.merge_log(repo, now: now, tz_offset: 0).groups)

    assert Enum.map(group.items, & &1.number) == [1, 2, 3]
    assert Enum.map(group.extra, & &1.number) == [4, 5, 6, 7, 8]
    assert group.more == 7
    assert group.more_wide == 2
  end

  test "the week counts the issues its PRs delivered, each once" do
    {:ok, repo} = Board.add_repository("fixture", "delivered")
    now = ~U[2026-11-06 15:00:00Z]

    for {number, closes, minutes} <- [
          {1, [7], 5},
          {2, [7, 8], 10},
          {3, [], 15},
          {4, [9], 60 * 24 * 9}
        ] do
      repo
      |> merged(number, "PR #{number}", "success", DateTime.add(now, -minutes, :minute))
      |> Ecto.Changeset.change(closes_issues: closes)
      |> Repo.update!()
    end

    log = Lanes.merge_log(repo, now: now, tz_offset: 0)

    # PR 4 is older than the week; PR 3 closes nothing; #7 is closed twice.
    assert log.total == 3
    assert log.issues == 2
    # The same rule for the day: today's three PRs delivered #7 and #8.
    assert List.last(log.days).issues == 2
    assert List.last(log.days).n == 3
  end

  test "a red remote check without local evidence is quiet, not a red day" do
    {:ok, repo} = Board.add_repository("fixture", "remote-only")
    now = ~U[2026-11-06 15:00:00Z]
    merged(repo, 9, "Remote only", "failure", now)

    log = Lanes.merge_log(repo, now: now, tz_offset: 0)
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
    digest = Lanes.digest(repo, board, now: now, last_visit: last_visit, tz_offset: 0)

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
    digest = Lanes.digest(repo, board, now: now, last_visit: nil, tz_offset: 0)

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

defmodule AgentBoard.LanesFrozenTest do
  @moduledoc "The frozen digest never claims a change it cannot see."
  use AgentBoard.DataCase, async: true

  alias AgentBoard.{Board, Lanes}

  test "without a successful sync the digest says it does not know" do
    {:ok, repo} = Board.add_repository("fixture", "frozen-digest")
    now = ~U[2026-11-06 15:00:00Z]
    board = %{running: [], question: [], ready: [], blocked: [], task_counts: %{queued: 0}}

    digest =
      Lanes.digest(repo, board,
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
