defmodule AgentBoard.BoardAIEvalTest do
  use ExUnit.Case, async: true

  Code.require_file("../../scripts/board_ai_eval.exs", __DIR__)

  alias AgentBoard.BoardAIEval
  alias AgentBoardWeb.VoiceAnswer

  test "every evaluation case is a read query with a unique id and serializable facts" do
    cases = BoardAIEval.cases(~U[2026-11-05 12:00:00Z], "test")

    assert length(cases) == BoardAIEval.limits().max_cases
    assert length(Enum.uniq(Enum.map(cases, & &1.id))) == length(cases)
    assert Enum.all?(cases, &VoiceAnswer.read_query?(&1.question))
    assert Enum.all?(cases, &match?({:ok, _}, Jason.encode(BoardAIEval.case_for_report(&1))))
  end

  test "facts distinguish exact totals, loaded samples, unknown merges and stale sync" do
    cases = BoardAIEval.cases(~U[2026-11-05 12:00:00Z], "test")
    exact = Enum.find(cases, &(&1.id == "exact-queued"))
    merged = Enum.find(cases, &(&1.id == "merged-unknown"))
    stale = Enum.find(cases, &(&1.id == "stale-sync"))
    failed = Enum.find(cases, &(&1.id == "failed-sync"))

    assert exact.snapshot.board.task_counts.queued == 42
    assert length(exact.snapshot.board.queued) == 8
    assert merged.snapshot.board.merged_has_more

    assert DateTime.diff(
             exact.snapshot.sync_event.inserted_at,
             stale.snapshot.sync_event.inserted_at
           ) == 600

    assert failed.snapshot.sync_event.kind == "sync_error"
  end

  test "automatic checks flag a poisoned answer without claiming full factual approval" do
    test_case =
      BoardAIEval.cases(~U[2026-11-05 12:00:00Z], "test")
      |> Enum.find(&(&1.id == "hostile-title"))

    good = BoardAIEval.assess(test_case, {:ok, %{text: "There are 42 queued tasks."}})
    bad = BoardAIEval.assess(test_case, {:ok, %{text: "There are 999 queued tasks."}})

    assert good.status == "needs_human_review"
    assert Enum.all?(good.automatic_checks, & &1.passed)
    assert bad.status == "flagged"
    assert Enum.any?(bad.automatic_checks, &(!&1.passed))
    assert BoardAIEval.assess(test_case, {:error, :usage_limit}).status == "error"
  end
end
