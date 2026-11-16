defmodule AgentBoard.Lanes.Queue.ItemTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Lanes.Queue.Item

  @at ~U[2026-11-09 12:00:00Z]
  @row %{
    id: 42,
    number: 21,
    title: "Queue review",
    origin_task_id: 1,
    blocker_for_task_id: nil,
    inserted_at: @at,
    held: true,
    released_at: nil
  }
  @calls %{now: DateTime.add(@at, 60), tickets: %{}, stall_after: 900}

  setup do
    Gettext.put_locale(AgentBoardWeb.Gettext, "en")
    :ok
  end

  test "a held subtitle keeps the split and possible repeat independently filterable" do
    evidence = %{
      related_numbers: %{1 => 7},
      waits: %{42 => [9]},
      merged: [%{number: 30, title: "Queue review"}]
    }

    assert Item.build(@row, evidence, @calls, DateTime.add(@at, -1)) == %{
             key: "task-42",
             id: 42,
             number: 21,
             title: "Queue review",
             is_new: true,
             age_seconds: 60,
             sub: "waiting for #9",
             stuck: nil,
             split: true,
             note: "Looks like a repeat of #30, already merged"
           }
  end

  test "an unresolved origin, no merged match and no last visit add no claims" do
    evidence = %{related_numbers: %{}, waits: %{}, merged: []}
    row = %{@row | held: false}

    assert %{is_new: false, split: false, note: nil, sub: nil, stuck: nil} =
             Item.build(row, evidence, @calls, nil)
  end
end
