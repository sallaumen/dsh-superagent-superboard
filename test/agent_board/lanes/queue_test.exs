defmodule AgentBoard.Lanes.QueueTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Queue

  test "related IDs preserve origin then blocker order and deduplicate across roles" do
    assert Queue.related_ids([
             %{origin_task_id: 12, blocker_for_task_id: 7},
             %{origin_task_id: 7, blocker_for_task_id: 9},
             %{origin_task_id: nil, blocker_for_task_id: 12},
             %{origin_task_id: 3, blocker_for_task_id: 3}
           ]) == [12, 7, 9, 3]
  end

  test "missing relationships need no lookup" do
    assert Queue.related_ids([]) == []
    assert Queue.related_ids([%{origin_task_id: nil, blocker_for_task_id: nil}]) == []
    assert Queue.related_ids([%{origin_task_id: nil, blocker_for_task_id: 7}]) == [7]
    assert Queue.related_ids([%{origin_task_id: 12, blocker_for_task_id: nil}]) == [12]
  end

  test "what a task unblocks takes precedence over its split origin" do
    assert Queue.relationship(12, 7) == {:unblocks, 12}
    assert Queue.relationship(12, nil) == {:unblocks, 12}
  end

  test "an origin is shown on its own and a missing relationship stays absent" do
    assert Queue.relationship(nil, 7) == {:split_from, 7}
    assert Queue.relationship(nil, nil) == nil
  end

  test "filter options depend on the whole queue, independent of the active filter and visible limit" do
    item = %{is_new: false, split: false, note: nil}
    compact = List.duplicate(item, 8)
    assert Queue.compact_limit() == 8

    for items <- [[], tl(compact), compact] do
      assert Queue.filter_options(Queue.page(items, :all, 1).counts) == []
    end

    large = [%{item | is_new: true, split: true} | compact]

    for limit <- [1, 8, 20] do
      page = Queue.page(large, :dupes, limit)
      assert page.items == []
      assert Queue.filter_options(page.counts) == [all: 9, new: 1, split: 1, dupes: 0]
    end
  end

  test "selection counts hidden repeats and relationships without needing card details" do
    at = ~U[2026-11-16 12:00:00Z]
    # No held/release/ticket evidence: selection needs none of the subtitle inputs.
    old = %{id: 1, title: "old", inserted_at: at, origin_task_id: 7, blocker_for_task_id: nil}

    new = %{
      old
      | id: 2,
        title: "repeat",
        inserted_at: DateTime.add(at, 1),
        blocker_for_task_id: 9
    }

    observed = %{
      rows: [old, new],
      related_numbers: %{7 => 17, 9 => 19},
      merged: [%{number: 4, title: "repeat"}]
    }

    page = Queue.select(observed, at, :all, 1)

    assert [%{row: ^old, is_new: false, relationship: {:split_from, 17}, repeat: nil}] =
             page.items

    assert %{counts: %{all: 2, split: 2, new: 1, dupes: 1}, total: 2, hidden: 1} = page

    assert [%{row: ^new, relationship: {:unblocks, 19}, repeat: %{number: 4}}] =
             Queue.select(observed, at, :dupes, 1).items
  end

  test "only visible holds without a call problem need blocker numbers" do
    now = ~U[2026-11-17 12:00:00Z]
    calls = %{now: now, tickets: %{}, stall_after: 900}
    row = %{id: 12, number: 12, held: true, released_at: nil}

    page = %{
      items: [
        %{row: row},
        %{row: %{row | id: 7, held: false}},
        %{row: %{row | id: 9, released_at: DateTime.add(now, -60)}},
        %{row: %{row | id: 8, released_at: DateTime.add(now, -59)}}
      ]
    }

    assert Queue.waiting_ids(page, calls) == [12, 8]
    assert Queue.waiting_ids(%{items: []}, calls) == []
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
