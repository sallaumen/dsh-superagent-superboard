defmodule AgentBoard.Board.RequestBatchTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Board.{RequestBatch, Task}

  test "retry keeps the original blocker number and returns receipts in the chosen order" do
    a = %{key: "a", body: "Measure"}
    b = %{key: "b", body: "Fix", depends_on: [a.key]}
    blocker = %Task{number: 101}
    sent_b = %{b | body: "Fix (depends on #101)"}

    retry =
      RequestBatch.for_retry([b, a], [{sent_b, {:error, :timeout}}, {a, {:ok, blocker, :created}}])

    assert RequestBatch.pending(retry) == [b]
    assert RequestBatch.confirmed_numbers(retry) == %{a.key => 101}
    created = {sent_b, {:ok, %Task{number: 102}, :created}}

    assert [^created, {%{key: "a"}, {:ok, ^blocker, :existing}}] =
             RequestBatch.merge_results(retry, [created])
  end
end
