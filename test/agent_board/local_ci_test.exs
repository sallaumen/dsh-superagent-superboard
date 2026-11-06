defmodule AgentBoard.LocalCITest do
  @moduledoc "The local gate comes from the executor's own report, not from a remote check."
  use ExUnit.Case, async: true

  alias AgentBoard.LocalCI

  @repo %{owner: "fixture", name: "local-ci"}

  defp ticket(reports, urls \\ ["https://github.com/fixture/local-ci/issues/1"]) do
    %{
      "channel_urls" => urls,
      "reports" =>
        Enum.map(reports, fn {summary, at} ->
          %{"state" => "ready", "summary" => summary, "at" => at}
        end)
    }
  end

  test "a precommit pass names the PRs in the ticket and keeps the billing hint" do
    report =
      "PR #21: verified on the final head: mix precommit passed (format, Credo strict 0 issues, 116 tests 0 failures). " <>
        "GitHub Actions never executed due to the repository billing/spending limit."

    status =
      LocalCI.by_pr(@repo, [ticket([{report, ~U[2026-11-06 12:00:00Z]}])])

    assert %{21 => %{state: :pass, remote_blocked: true} = ci} = status
    assert ci.detail =~ "mix precommit passed"
    assert ci.detail =~ "116 tests"
  end

  test "the latest local evidence wins" do
    pass = {"PR #21: mix precommit green (89 tests, 0 failures).", ~U[2026-11-06 11:00:00Z]}
    fail = {"PR #21: mix precommit failed (2 tests, 1 failure).", ~U[2026-11-06 12:00:00Z]}

    status = LocalCI.by_pr(@repo, [ticket([pass, fail])])

    assert status[21].state == :fail
    assert status[21].remote_blocked == false
  end

  test "a later report without CI does not erase the earlier pass" do
    pass =
      {"PR #21 merged; mix precommit passed (100 tests, 0 failures).", ~U[2026-11-05 23:38:00Z]}

    later =
      {"Both follow-up issues are resolved: PR #21 and PR #24 merged.", ~U[2026-11-05 23:52:00Z]}

    status = LocalCI.by_pr(@repo, [ticket([pass, later])])

    # The pass names #21; the later summary names #24 but has no local check.
    assert status[21].state == :pass
    refute Map.has_key?(status, 24)
  end

  test "another repository and a report without precommit stay unknown" do
    other =
      ticket([{"mix precommit passed (1 test, 0 failures).", ~U[2026-11-06 12:00:00Z]}], [
        "https://github.com/other/repo/issues/1"
      ])

    no_ci = ticket([{"PR #42 is ready for review.", ~U[2026-11-06 12:00:00Z]}])

    assert LocalCI.by_pr(@repo, [other, no_ci]) == %{}
  end
end
