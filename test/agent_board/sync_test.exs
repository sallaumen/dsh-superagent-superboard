defmodule AgentBoard.SyncTest do
  @moduledoc "The pure state mapping: tickets, reviews and checks."
  use ExUnit.Case, async: true

  alias AgentBoard.Sync

  defp ticket(assignment, report, outcome) do
    %{"assignment" => assignment, "report" => report, "ended_outcome" => outcome}
  end

  test "a running ticket wins" do
    assert Sync.ticket_state(ticket("running", nil, nil)) == "running"
  end

  test "a ready report wins over a queued assignment" do
    assert Sync.ticket_state(ticket("queued", "ready", nil)) == "ready"
  end

  test "a blocked report wins" do
    assert Sync.ticket_state(ticket("blocked", "blocked", nil)) == "blocked"
  end

  test "a merged outcome is done" do
    assert Sync.ticket_state(ticket("ended", nil, "merged")) == "done"
  end

  test "an ended ticket without an outcome has no overlay" do
    assert Sync.ticket_state(ticket("ended", nil, nil)) == nil
  end

  test "a stopped ticket has no overlay" do
    assert Sync.ticket_state(ticket("ended", nil, "stopped")) == nil
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
    assert Sync.ticket_state(waiting("Which API should the board use?")) == "question"
  end

  test "a waiting report whose newest agent comment asks is a question" do
    assert Sync.ticket_state(waiting("Asked the owner about the API."), asked?: true) ==
             "question"

    assert Sync.ticket_state(waiting("Asked the owner about the API."),
             asked?: fn -> true end
           ) == "question"
  end

  test "a waiting ticket that opened its own PR is ready for review" do
    ticket = waiting("CI confirmed as the billing failure. No code change made.")
    assert Sync.ticket_state(Map.put(ticket, "own_threads", [28])) == "ready"
  end

  test "a waiting report that names a PR for review is ready without the thread" do
    assert Sync.ticket_state(waiting("PR #28 remains ready for human review.")) == "ready"
  end

  test "a waiting report without a question or a PR is blocked" do
    assert Sync.ticket_state(waiting("Cannot reach the package registry.")) == "blocked"
  end

  test "a waiting report with no summary is blocked, not a question" do
    assert Sync.ticket_state(waiting(nil)) == "blocked"
  end

  test "a question beats the open PR when the agent asks" do
    ticket = waiting("PR #28 is open. Should it also cover the boss?")
    assert Sync.ticket_state(Map.put(ticket, "own_threads", [28])) == "question"
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
