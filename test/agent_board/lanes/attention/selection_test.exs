defmodule AgentBoard.Lanes.Attention.SelectionTest do
  use ExUnit.Case, async: true
  alias AgentBoard.Lanes.Attention.Selection

  @now ~U[2026-11-16 12:00:00Z]
  @ctx %{
    now: @now,
    agent: :unknown,
    tickets: %{},
    stall_after: 60,
    silences: %{1 => %{seconds: 60}}
  }
  test "a mixed board keeps call verdicts and tie order; an outage groups only eligible work" do
    at = DateTime.add(@now, -2400)
    run = %{number: 1, state_changed_at: at, size: "S"}
    slow = %{run | number: 2}
    fresh = %{run | number: 3, state_changed_at: @now}
    failed = %{number: 4, held: true, released_at: at}
    unanswered = %{number: 5, held: false, released_at: at}
    waiting = %{number: 6, held: true, released_at: nil}

    board = %{
      running: [run, fresh, slow],
      queued: [failed, waiting, unanswered],
      blocked: [%{number: 7}],
      retrying: [%{number: 10}],
      ready: [%{number: 8}],
      question: [%{number: 9}]
    }

    independent = [%{task: %{number: 8}, kind: :review}, %{task: %{number: 9}, kind: :question}]
    assert %{waiting: nil, visible: visible} = Selection.plan(board, @ctx)

    assert visible ==
             [
               %{task: %{number: 7}, kind: :blocked},
               %{task: run, kind: :stalled},
               %{task: slow, kind: :slow},
               %{task: failed, kind: :unanswered, problem: :failed},
               %{task: unanswered, kind: :unanswered, problem: :unanswered}
             ] ++ independent

    assert Selection.plan(board, %{@ctx | agent: :down}) == %{visible: independent, waiting: 6}
  end

  test "review evidence follows selected reviews, including when an outage hides blocked tasks" do
    board = %{ready: [%{id: 8}, %{id: 2}], blocked: [%{id: 3}], question: [%{id: 7}]}

    for agent <- [:up, :down] do
      page = Selection.plan(board, %{@ctx | agent: agent})
      assert Selection.review_tasks(page.visible) == [%{id: 8}, %{id: 2}]
    end

    assert Selection.review_tasks([%{kind: :question, task: %{id: 7}}]) == []
  end

  test "zero waiting still shows an outage, while an available agent leaves an empty list alone" do
    assert Selection.plan(%{}, %{@ctx | agent: :down}) == %{waiting: 0, visible: []}
    assert Selection.plan(%{}, %{@ctx | agent: :up}) == %{waiting: nil, visible: []}
  end
end
