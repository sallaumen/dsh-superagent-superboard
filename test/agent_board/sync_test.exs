defmodule AgentBoard.SyncTest do
  @moduledoc "The pure state mapping: tickets, reviews and checks."
  use ExUnit.Case, async: true

  alias AgentBoard.{Sync, Tickets}

  defp ticket(assignment, report, outcome) do
    %{"assignment" => assignment, "report" => report, "ended_outcome" => outcome}
  end

  test "a running ticket wins" do
    assert Tickets.state(ticket("running", nil, nil)) == "running"
  end

  test "a ready report wins over a queued assignment" do
    assert Tickets.state(ticket("queued", "ready", nil)) == "ready"
  end

  test "a blocked report wins" do
    assert Tickets.state(ticket("blocked", "blocked", nil)) == "blocked"
  end

  test "a merged outcome is done" do
    assert Tickets.state(ticket("ended", nil, "merged")) == "done"
  end

  test "a merged outcome is done even when the last report is ready" do
    assert Tickets.state(ticket("ended", "ready", "merged")) == "done"
  end

  test "a merged outcome is done even when the ticket was waiting on its own PR" do
    ticket =
      "PR #28 remains ready for human review."
      |> waiting()
      |> Map.merge(%{"ended_outcome" => "merged", "own_threads" => [28]})

    assert Tickets.state(ticket) == "done"
  end

  test "an ended ticket without an outcome has no overlay" do
    assert Tickets.state(ticket("ended", nil, nil)) == nil
  end

  test "a stopped ticket has no overlay" do
    assert Tickets.state(ticket("ended", nil, "stopped")) == nil
  end

  describe "a failed ticket" do
    # The runner's ticket, normalized: one failed Assignment after `history`.
    defp failed(summary, history \\ []) do
      previous =
        for {ended, i} <- Enum.with_index(history) do
          %{
            "id" => "a#{i}",
            "state" => "ended",
            "report" => %{"state" => "failed"},
            "endedReason" => ended
          }
        end

      AgentBoard.AgentState.normalize(%{
        "id" => "t1",
        "assignments" =>
          previous ++
            [
              %{
                "id" => "latest",
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

    test "is retrying while the board retries a transient failure by itself" do
      assert Tickets.state(failed("LlmError: DeepSeek Messages transport failed")) ==
               "retrying"
    end

    test "is blocked when the failure needs a person or the retries ran out" do
      assert Tickets.state(failed("Tests failed: 3")) == "blocked"

      assert Tickets.state(
               failed("LlmError: DeepSeek Messages transport failed", ~w(retried retried retried))
             ) == "blocked"
    end

    test "is retrying while a retry waits for a worker" do
      ticket =
        AgentBoard.AgentState.normalize(%{
          "id" => "t1",
          "assignments" => [
            %{
              "id" => "a",
              "state" => "ended",
              "report" => %{"state" => "failed"},
              "endedReason" => "retried"
            },
            %{"id" => "b", "state" => "pending"}
          ]
        })

      assert Tickets.state(ticket) == "retrying"
    end
  end

  test "a single approval is approved" do
    assert Sync.review_rollup([%{"state" => "APPROVED"}]) == "approved"
  end

  test "changes requested beats an approval" do
    assert Sync.review_rollup([%{"state" => "APPROVED"}, %{"state" => "CHANGES_REQUESTED"}]) ==
             "changes_requested"
  end

  test "comments alone are pending" do
    assert Sync.review_rollup([%{"state" => "COMMENTED"}]) == "pending"
  end

  test "no reviews is none" do
    assert Sync.review_rollup([]) == "none"
  end

  test "all checks passing is success" do
    checks = [
      %{"name" => "test", "status" => "completed", "conclusion" => "success"},
      %{"name" => "lint", "status" => "completed", "conclusion" => "success"}
    ]

    assert Sync.checks_rollup(checks) == {"success", ""}
  end

  test "a failure names the check" do
    checks = [
      %{"name" => "test", "status" => "completed", "conclusion" => "success"},
      %{"name" => "lint", "status" => "completed", "conclusion" => "failure"}
    ]

    assert Sync.checks_rollup(checks) == {"failure", "lint"}
  end

  test "a running check is pending" do
    checks = [
      %{"name" => "test", "status" => "completed", "conclusion" => "success"},
      %{"name" => "build", "status" => "in_progress", "conclusion" => nil}
    ]

    assert Sync.checks_rollup(checks) == {"pending", ""}
  end

  test "no checks is none" do
    assert Sync.checks_rollup([]) == {"none", ""}
  end

  # `waiting` means the executor needs input. Mapping it blindly to a
  # question put #27 in "Precisa de você" with nothing to answer: the
  # ticket had opened PR #28 and was waiting for a review.
  test "a waiting report with a question in it is a question" do
    assert Tickets.state(waiting("Which API should the board use?")) == "question"
  end

  test "a waiting report whose newest agent comment asks is a question" do
    assert Tickets.state(waiting("Asked the owner about the API."), asked?: true) ==
             "question"

    assert Tickets.state(waiting("Asked the owner about the API."),
             asked?: fn -> true end
           ) == "question"
  end

  test "a waiting ticket that opened its own PR is ready for review" do
    ticket = waiting("CI confirmed as the billing failure. No code change made.")
    assert Tickets.state(Map.put(ticket, "own_threads", [28])) == "ready"
  end

  test "a waiting report that names a PR for review is ready without the thread" do
    assert Tickets.state(waiting("PR #28 remains ready for human review.")) == "ready"
  end

  test "a waiting report without a question or a PR is blocked" do
    assert Tickets.state(waiting("Cannot reach the package registry.")) == "blocked"
  end

  test "a waiting report with no summary is blocked, not a question" do
    assert Tickets.state(waiting(nil)) == "blocked"
  end

  test "a question beats the open PR when the agent asks" do
    ticket = waiting("PR #28 is open. Should it also cover the boss?")
    assert Tickets.state(Map.put(ticket, "own_threads", [28])) == "question"
  end

  # The workpad says it in a field: no "?" in the summary is needed, and a
  # filled Bloqueio beats the PR the ticket opened.
  test "a waiting ticket whose workpad has a question is a question without any ?" do
    ticket = waiting("Waiting for the owner.") |> Map.put("own_threads", [28])

    assert Tickets.state(ticket, workpad: workpad(question: "Devo manter o boss")) ==
             "question"

    assert Tickets.state(ticket, workpad: fn -> workpad(question: "Devo manter o boss") end) ==
             "question"
  end

  test "a waiting ticket whose workpad has a blockage is blocked even with its own PR" do
    ticket = waiting("PR #28 is open for review.") |> Map.put("own_threads", [28])

    assert Tickets.state(ticket, workpad: workpad(blockage: "Sem acesso ao registry")) ==
             "blocked"
  end

  test "a workpad with both fields empty leaves the text heuristic in charge" do
    ticket = waiting("PR #28 remains ready for human review.")

    assert Tickets.state(ticket, workpad: workpad([])) == "ready"
    assert Tickets.state(waiting("Which API?"), workpad: workpad([])) == "question"

    assert Tickets.state(waiting("Cannot reach the registry."), workpad: workpad([])) ==
             "blocked"
  end

  test "a ticket without a workpad behaves as before" do
    ticket = waiting("Asked the owner about the API.")

    assert Tickets.state(ticket, workpad: nil) == "blocked"
    assert Tickets.state(ticket, workpad: fn -> nil end, asked?: true) == "question"
  end

  defp workpad(fields) do
    Map.merge(
      %{plan: nil, validation: nil, question: nil, blockage: nil, resume: nil, pull_requests: []},
      Map.new(fields)
    )
  end

  describe "a person's answer the worker read" do
    # arena-rogue #208, 2026-11-10: the owner answered at 14:44, the worker read
    # it a second later and worked for 35 minutes under a "Blocked" card,
    # because the report it had written before the answer still said waiting.
    @waited ~U[2026-11-10 17:00:44Z]
    @read ~U[2026-11-10 17:45:12Z]

    defp answered(report \\ "waiting") do
      waiting("A chave da OpenAI está sem créditos.")
      |> Map.merge(%{
        "report" => report,
        "report_at" => @waited,
        "idle_at" => @waited,
        "answered_at" => @read
      })
    end

    test "puts a waiting ticket back to work, whatever the agent wrote since" do
      assert Tickets.state(answered()) == "running"
      # the workpad still carries the old block, and "On it" asks nothing
      assert Tickets.state(answered(), workpad: %{blockage: "sem créditos"}) == "running"
      assert Tickets.state(answered(), workpad: %{question: "Qual chave?"}) == "running"
      assert Tickets.state(answered(), asked?: false) == "running"
    end

    test "puts a blocked report back to work too" do
      assert Tickets.state(answered("blocked")) == "running"
    end

    test "does not count before it is read, or when it is older than the report" do
      assert Tickets.state(Map.put(answered(), "answered_at", nil)) == "blocked"

      asks_again = Map.put(answered(), "report_at", DateTime.add(@read, 48, :second))
      assert Tickets.state(asks_again) == "blocked"
      assert Tickets.state(asks_again, workpad: %{question: "E agora?"}) == "question"
    end

    test "does not count once the worker went idle after it, or the ticket ended" do
      idle_again = Map.put(answered(), "idle_at", DateTime.add(@read, 600, :second))
      assert Tickets.state(idle_again) == "blocked"

      ended = Map.put(answered(), "ended_at", DateTime.add(@read, 60, :second))
      assert Tickets.state(ended) == "blocked"
    end

    test "changes nothing for a report that is not waiting for anyone" do
      ticket = Map.merge(answered(), %{"report" => "ready", "own_threads" => [28]})
      assert Tickets.state(ticket) == "ready"
      assert Tickets.answered_at(ticket) == nil
      assert Tickets.answered_at(answered()) == @read
    end
  end

  defp waiting(summary) do
    %{
      "assignment" => "running",
      "report" => "waiting",
      "report_summary" => summary,
      "ended_outcome" => nil,
      "own_threads" => []
    }
  end
end
