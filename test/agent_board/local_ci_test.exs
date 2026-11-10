defmodule AgentBoard.LocalCITest do
  @moduledoc "The local gate comes from the executor's own report, not from a remote check."
  use ExUnit.Case, async: true

  alias AgentBoard.LocalCI

  @repo %{owner: "fixture", name: "local-ci"}

  # The Portuguese sentences below are the proof that pt-BR did not change.
  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "pt_BR")
    :ok
  end

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

    # The pass names #21; #24 is the same ticket's later PR, so it inherits
    # the ticket gate with the evidence PR named in the tooltip.
    assert status[21].state == :pass
    assert status[21].scope == :pr
    assert status[24].state == :pass
    assert status[24].scope == :ticket
    assert status[24].evidence_pr == 21
    assert status[24].detail == status[21].detail
  end

  @head "44653e8abcdef0123456789abcdef0123456789a"

  defp workpad(validation, prs \\ []) do
    %{plan: nil, question: nil, blockage: nil, pull_requests: prs, validation: validation}
  end

  defp gate(detail, passed?, sha),
    do: %{command: "mix precommit", passed?: passed?, sha: sha, detail: detail}

  test "the workpad's Validação beats the reports and names the sha it ran on" do
    report = {"PR #21: mix precommit failed (2 tests, 1 failure).", ~U[2026-11-06 12:00:00Z]}
    ticket = ticket([report]) |> Map.put("numbers", [1])
    gate = gate("mix precommit: passou (326 testes) em 44653e8", true, "44653e8")

    status =
      LocalCI.by_pr(@repo, [ticket], workpads: %{1 => workpad(gate)}, heads: %{21 => @head})

    assert %{21 => %{state: :pass, scope: :workpad, sha: "44653e8", head_sha: @head} = ci} =
             status

    assert ci.detail == "mix precommit: passou (326 testes) em 44653e8"
    refute ci.remote_blocked
  end

  test "a gate on another commit than the PR head is stale, never a pass" do
    ticket = ticket([{"PR #21 opened.", ~U[2026-11-06 12:00:00Z]}]) |> Map.put("numbers", [1])
    gate = gate("mix precommit: passou (326 testes) em 44653e8", true, "44653e8")
    heads = %{21 => "9f1c2ab0000000000000000000000000000000000"}

    assert %{21 => %{state: :stale, detail: detail}} =
             LocalCI.by_pr(@repo, [ticket], workpads: %{1 => workpad(gate)}, heads: heads)

    assert detail ==
             "mix precommit: passou (326 testes) em 44653e8, mas o head do PR é 9f1c2ab: o gate não cobre o commit atual."
  end

  test "the note the board adds to a stale gate follows the viewer's language" do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    ticket = ticket([{"PR #21 opened.", ~U[2026-11-06 12:00:00Z]}]) |> Map.put("numbers", [1])
    gate = gate("mix precommit: passed in 44653e8", true, "44653e8")
    heads = %{21 => "9f1c2ab0000000000000000000000000000000000"}

    assert %{21 => %{detail: detail}} =
             LocalCI.by_pr(@repo, [ticket], workpads: %{1 => workpad(gate)}, heads: heads)

    assert detail ==
             "mix precommit: passed in 44653e8, but the PR's head is 9f1c2ab: " <>
               "the gate does not cover the current commit."
  end

  test "an unknown head cannot contradict the gate, and a failed gate fails" do
    ticket = ticket([{"PR #21 opened.", ~U[2026-11-06 12:00:00Z]}]) |> Map.put("numbers", [1])
    pass = gate("mix precommit: passou em 44653e8", true, "44653e8")
    fail = gate("mix precommit: falhou (2 falhas) em 44653e8", false, "44653e8")

    assert %{21 => %{state: :pass, head_sha: nil}} =
             LocalCI.by_pr(@repo, [ticket], workpads: %{1 => workpad(pass)})

    assert %{21 => %{state: :fail}} =
             LocalCI.by_pr(@repo, [ticket],
               workpads: %{1 => workpad(fail)},
               heads: %{21 => @head}
             )
  end

  test "the gate covers the ticket's own PR and the PRs the workpad names" do
    ticket = ticket([]) |> Map.merge(%{"numbers" => [1], "own_threads" => [21]})
    gate = gate("mix precommit: passou em 44653e8", true, "44653e8")

    status = LocalCI.by_pr(@repo, [ticket], workpads: %{1 => workpad(gate, [24])})

    assert Map.keys(status) |> Enum.sort() == [21, 24]
  end

  test "a workpad whose Validação names no result leaves the reports in charge" do
    pass = {"PR #21: mix precommit green (89 tests, 0 failures).", ~U[2026-11-06 11:00:00Z]}
    ticket = ticket([pass]) |> Map.put("numbers", [1])
    pending = gate("rodando ainda", nil, nil)

    assert %{21 => %{state: :pass, scope: :pr}} =
             LocalCI.by_pr(@repo, [ticket], workpads: %{1 => workpad(pending)})

    assert %{21 => %{state: :pass, scope: :pr}} =
             LocalCI.by_pr(@repo, [ticket], workpads: %{1 => workpad(nil)})
  end

  test "a workpad whose issue has no ticket still gates the PRs it names" do
    gate = gate("mix precommit: passou em 44653e8", true, "44653e8")

    assert %{30 => %{state: :pass, scope: :workpad}} =
             LocalCI.by_pr(@repo, [],
               workpads: %{7 => workpad(gate, [30])},
               heads: %{30 => @head}
             )
  end

  test "a workpad with an empty Validação and no ticket yields no gate" do
    status =
      LocalCI.by_pr(@repo, [],
        workpads: %{7 => workpad(nil, [30])},
        heads: %{30 => @head}
      )

    assert status == %{}
  end

  for {summary, state} <- [
        {"PR #21: mix precommit: passou, nenhum teste falhou", :pass},
        {"PR #21: mix precommit: passou (0 failed)", :pass},
        {"PR #21: mix precommit passed with no failing tests", :pass},
        {"PR #21: mix precommit não passou", :fail},
        {"PR #21: mix precommit nao passou", :fail},
        {"PR #21: mix precommit did not pass", :fail},
        {"PR #21: mix precommit didn't pass", :fail},
        {"PR #21: mix precommit falhou (2 falhas)", :fail},
        {"PR #21: mix precommit failed: 2 failures", :fail}
      ] do
    test "a report reads #{inspect(summary)}" do
      status = LocalCI.by_pr(@repo, [ticket([{unquote(summary), ~U[2026-11-06 12:00:00Z]}])])

      assert %{21 => %{state: unquote(state)}} = status
    end
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
