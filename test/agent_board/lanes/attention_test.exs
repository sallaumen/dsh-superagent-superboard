defmodule AgentBoard.Lanes.AttentionTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Attention

  defp item(kind, is_new, age), do: %{kind: kind, is_new: is_new, age_seconds: age}

  test "kind wins even over newer or older items at a lower priority" do
    kinds = [:slow, :question, :review, :unanswered, :blocked, :cifail, :agent_down]

    rows =
      Enum.with_index(kinds, fn kind, index -> item(kind, kind != :agent_down, 60 - index) end)

    assert Enum.map(Attention.sort(rows), & &1.kind) == Enum.reverse(kinds)
    assert Attention.sort([]) == []
  end

  test "stalled and unanswered share priority: novelty wins over age, then oldest comes first" do
    seen = item(:unanswered, false, 600)
    fresh = item(:stalled, true, 1)
    older = item(:unanswered, true, 90)
    unknown = item(:stalled, false, nil)
    assert Attention.sort([unknown, seen, fresh, older]) == [older, fresh, seen, unknown]
  end

  test "exact ties keep either input order, including an unknown age tied with zero" do
    stalled = item(:stalled, true, nil)
    unanswered = item(:unanswered, true, 0)

    for pair <- [[stalled, unanswered], [unanswered, stalled]],
        do: assert(Attention.sort(pair) == pair)
  end

  test "an outage groups dependent needs and retries, leaving owner actions in input order" do
    question = %{kind: :question, id: 10}
    review = %{kind: :review, id: 12}

    needs = [
      %{kind: :stalled},
      question,
      %{kind: :slow},
      review,
      %{kind: :unanswered},
      %{kind: :blocked}
    ]

    assert Attention.outage_summary(needs, 2) == {6, [question, review]}
  end

  test "an outage can have nothing waiting or only retries" do
    assert Attention.outage_summary([], 0) == {0, []}
    assert Attention.outage_summary([], 2) == {2, []}
  end
end
