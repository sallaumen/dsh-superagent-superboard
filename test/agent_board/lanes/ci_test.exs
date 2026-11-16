defmodule AgentBoard.Lanes.CITest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Lanes
  alias AgentBoard.Lanes.CI
  alias AgentBoard.Lanes.MergeHistory
  alias AgentBoard.LocalCI

  test "green remote checks cannot validate a local pass recorded for another commit" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")

    pull = %PullRequest{
      number: 21,
      checks_state: "success",
      head_sha: "9f1c2ab0000000000000000000000000000000000"
    }

    workpad = %{
      pull_requests: [21],
      validation: %{sha: "44653e8", passed?: true, detail: "mix precommit passed on 44653e8"}
    }

    local =
      LocalCI.by_pr(%{owner: "fixture", name: "board"}, [],
        workpads: %{7 => workpad},
        heads: %{21 => pull.head_sha}
      )

    assert {:unknown, :stale} = CI.classify(pull, local[21])
    assert {"unknown", "Local CI unknown", detail} = Lanes.ci(pull, local)
    assert detail =~ "44653e8"
    assert detail =~ "9f1c2ab"
    assert {"pass", "CI passed", _} = Lanes.ci(pull, %{})
  end

  test "local pass or failure wins; without a report only remote success is a pass" do
    red = %PullRequest{checks_state: "failure"}
    green = %PullRequest{checks_state: "success"}
    assert CI.classify(red, %{state: :pass}) == {:pass, :local_pass}
    assert CI.classify(green, %{state: :fail, detail: "1 failure"}) == {:fail, :local_fail}
    assert CI.classify(red, nil) == {:unknown, :remote_failure}
    assert CI.classify(%PullRequest{checks_state: "pending"}, nil) == {:unknown, :pending}
    assert CI.classify(%PullRequest{}, nil) == {:unknown, :no_checks}
  end

  test "stale and missing reports do not count as local outcomes" do
    assert CI.local_result(%{state: :pass}) == :pass
    assert CI.local_result(%{state: :fail}) == :fail
    assert CI.local_result(%{state: :stale}) == nil
    assert CI.local_result(nil) == nil

    green = %PullRequest{number: 21, closes_issues: [], checks_state: "success"}
    assert CI.classify(green, nil) == {:pass, :remote_pass}
    assert %{n: 1, ok: 0, fail: 0} = MergeHistory.day_totals([green], %{})
  end
end
