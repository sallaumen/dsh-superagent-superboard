defmodule AgentBoard.Lanes.QueueTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Queue

  test "what a task unblocks takes precedence over its split origin" do
    assert Queue.relationship(12, 7) == {:unblocks, 12}
    assert Queue.relationship(12, nil) == {:unblocks, 12}
  end

  test "an origin is shown on its own and a missing relationship stays absent" do
    assert Queue.relationship(nil, 7) == {:split_from, 7}
    assert Queue.relationship(nil, nil) == nil
  end

  describe "page/3" do
    @first %{id: 7, is_new: false, split: true, note: nil}
    @second %{id: 2, is_new: true, split: true, note: "repeat"}
    @last %{id: 9, is_new: true, split: false, note: nil}
    @items [@first, @second, @last]

    test "counts overlapping categories on the full queue, but counts hidden rows after filtering" do
      assert Queue.page(@items, :new, 1) == %{
               items: [@second],
               total: 2,
               hidden: 1,
               counts: %{all: 3, new: 2, split: 2, dupes: 1},
               filter: :new,
               limit: 1
             }

      assert Queue.page(@items, :split, 8).items == [@first, @second]
      assert Queue.page(@items, :dupes, 8).items == [@second]
    end

    test "the default and unknown filters preserve order; empty matches have no hidden rows" do
      for filter <- [:all, :unknown], do: assert(Queue.page(@items, filter, 8).items == @items)
      assert %{items: [], total: 0, hidden: 0, counts: %{all: 1}} = Queue.page([@first], :new, 8)
    end
  end
end
