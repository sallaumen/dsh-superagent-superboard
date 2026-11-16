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

  describe "started_at/3" do
    @at ~U[2026-11-10 12:00:00Z]

    test "silence and long runs date from their thresholds, not the last signal or start" do
      task = %{number: 12, size: "S", state_changed_at: @at}
      context = %{silences: %{12 => %{at: @at}}, stall_after: 90}
      assert Attention.started_at(task, :stalled, context) == DateTime.add(@at, 90)
      assert Attention.started_at(task, :slow, context) == DateTime.add(@at, 20 * 60)
    end

    test "an incomplete call dates from the claim, an unanswered call from its deadline" do
      task = %{held: true, released_at: @at}
      assert Attention.started_at(task, :unanswered, %{stall_after: 90}) == @at

      assert Attention.started_at(%{task | held: false}, :unanswered, %{stall_after: 90}) ==
               DateTime.add(@at, 90)
    end

    test "ordinary needs prefer a state transition, then update, then insertion" do
      task = %{
        state_changed_at: DateTime.add(@at, 10),
        updated_at: DateTime.add(@at, 20),
        inserted_at: @at
      }

      assert Attention.started_at(task, :review, %{}) == task.state_changed_at

      assert Attention.started_at(%{task | state_changed_at: nil}, :question, %{}) ==
               task.updated_at

      assert Attention.started_at(%{task | state_changed_at: nil, updated_at: nil}, :blocked, %{}) ==
               @at
    end
  end
end
