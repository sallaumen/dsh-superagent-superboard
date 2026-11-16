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
    candidate = %{row: @row, relationship: {:split_from, 7}, is_new: true, repeat: %{number: 30}}

    assert Item.build(candidate, %{42 => [9]}, @calls) == %{
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
    candidate = %{row: %{@row | held: false}, relationship: nil, is_new: false, repeat: nil}

    assert %{is_new: false, split: false, note: nil, sub: nil, stuck: nil} =
             Item.build(candidate, %{}, @calls)
  end
end
