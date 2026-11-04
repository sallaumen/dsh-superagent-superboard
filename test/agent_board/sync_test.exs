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
end
