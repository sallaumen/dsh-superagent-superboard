defmodule AgentBoard.Lanes.CI.BadgeTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.PullRequest
  alias AgentBoard.Lanes.CI.Badge

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "a local ticket pass explains its source; a remote pass is not marked local" do
    pull = %PullRequest{checks_state: "failure"}

    local = %{
      state: :pass,
      detail: "mix precommit passed",
      scope: :ticket,
      evidence_pr: 12,
      remote_blocked: true
    }

    badge = Badge.describe(pull, local)
    assert %{state: "pass", note: "Local CI passed", local: true} = badge
    assert badge.title =~ "GitHub Actions failed (billing/no credit on GitHub)"
    assert badge.title =~ "report cites #12"
    assert badge.title =~ "mix precommit passed"
    assert %{state: "pass", local: false} = Badge.describe(%{pull | checks_state: "success"}, nil)
  end

  test "failed remote names are deduplicated in order without claiming a local failure" do
    pull = %PullRequest{checks_state: "failure", checks_failed: " lint, tests, ,lint "}

    assert %{
             state: "unknown",
             local: false,
             title: "GitHub Actions failed on lint and tests; no evidence of local CI."
           } = Badge.describe(pull, nil)

    assert %{title: "GitHub Actions failed; no evidence of local CI."} =
             Badge.describe(%{pull | checks_failed: nil}, nil)

    long_name = String.duplicate("á", 81)

    assert Badge.describe(%{pull | checks_failed: long_name}, nil).title ==
             "GitHub Actions failed on " <>
               String.duplicate("á", 80) <> "; no evidence of local CI."
  end
end
