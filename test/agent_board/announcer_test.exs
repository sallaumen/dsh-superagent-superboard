defmodule AgentBoard.AnnouncerTest do
  @moduledoc "What the agent says when the board changes: the pure diff."
  use ExUnit.Case, async: true

  alias AgentBoard.Announcer

  defp task(id, title, state), do: %{id: id, title: title, state: state}

  defp board(tasks \\ []) do
    Enum.reduce(tasks, %{running: [], ready: [], blocked: [], queued: [], merged: []}, fn t,
                                                                                          acc ->
      Map.update!(acc, t.state, &[t | &1])
    end)
  end

  defp sync(kind, errors \\ 0, id \\ 1) do
    %{id: id, kind: kind, payload: %{"errors" => errors}}
  end

  test "a move between live lanes is spoken" do
    old = board([task(1, "Ship it", :queued)])
    new = board([task(1, "Ship it", :running)])

    assert Announcer.board_changes(old, new, nil, nil) == ["Task 'Ship it' is now running."]
  end

  test "a task that appears is not announced" do
    old = board([])
    new = board([task(1, "Ship it", :queued)])

    assert Announcer.board_changes(old, new, nil, nil) == []
  end

  test "a task moving into the merged history is not announced" do
    old = board([task(1, "Ship it", :queued)])
    new = board([task(1, "Ship it", :merged)])

    assert Announcer.board_changes(old, new, nil, nil) == []
  end

  test "a new sync failure is announced once" do
    assert Announcer.board_changes(board([]), board([]), nil, sync("sync_error")) ==
             ["The sync failed. Showing saved data."]

    # The same failure keeps repeating every minute: silence.
    assert Announcer.board_changes(board([]), board([]), sync("sync_error"), sync("sync_error")) ==
             []
  end

  test "more errors than the last sync are announced, a clean sync is not" do
    assert Announcer.board_changes(board([]), board([]), sync("sync", 0), sync("sync", 2)) ==
             ["The sync finished with 2 errors."]

    assert Announcer.board_changes(board([]), board([]), sync("sync", 2), sync("sync", 0)) == []
  end

  test "a burst is capped" do
    old =
      board([
        task(1, "One", :queued),
        task(2, "Two", :queued),
        task(3, "Three", :queued)
      ])

    new =
      board([
        task(1, "One", :running),
        task(2, "Two", :running),
        task(3, "Three", :running)
      ])

    changes = Announcer.board_changes(old, new, nil, nil)
    assert length(changes) == 2
    assert Enum.all?(changes, &(&1 =~ "is now running."))
  end

  test "a long answer is cut at a word boundary" do
    long = String.duplicate("word ", 100)

    assert byte_size(Announcer.speakable_answer(long, 40)) <= 40
    refute Announcer.speakable_answer(long, 40) =~ ~r/\s+\z/

    short = "All clear."
    assert Announcer.speakable_answer(short) == short
  end
end
