defmodule AgentBoard.AnnouncerTest do
  use ExUnit.Case, async: true

  alias AgentBoard.Announcer
  alias AgentBoard.Voice.Phrases

  defp task(id, title, state), do: %{id: id, title: title, state: state}

  defp board(tasks \\ []) do
    empty = %{
      running: [],
      retrying: [],
      question: [],
      ready: [],
      blocked: [],
      queued: [],
      merged: []
    }

    Enum.reduce(tasks, empty, fn t, acc -> Map.update!(acc, t.state, &[t | &1]) end)
  end

  test "no automatic speech is the default, including a task needing attention" do
    old = board([task(1, "A", :running)])
    new = board([task(1, "A", :question)])
    assert Announcer.board_changes(old, new, nil, nil) == []
  end

  test "question, block and review are individually selectable" do
    old =
      board([
        task(1, "Question", :running),
        task(2, "Blocked", :running),
        task(3, "Review", :running)
      ])

    new =
      board([
        task(1, "Question", :question),
        task(2, "Blocked", :blocked),
        task(3, "Review", :ready)
      ])

    assert Announcer.board_changes(old, new, nil, nil, enabled: [:blocked]) ==
             [Phrases.attention("pt-BR", :blocked, "Blocked", 0)]

    assert Announcer.board_changes(old, new, nil, nil,
             enabled: [:question, :ready],
             language: "en-US"
           ) == [
             Phrases.attention("en-US", :question, "Question", 0),
             Phrases.attention("en-US", :ready, "Review", 1)
           ]
  end

  test "progress, queue, sync errors and slow or stalled timers never speak" do
    old = board([task(1, "Running", :queued), task(2, "Queued", :running)])
    new = board([task(1, "Running", :running), task(2, "Queued", :queued)])
    sync = %{kind: "sync_error", id: 2}
    needs = {[], [%{kind: :stalled, key: "task-1", title: "Running"}]}

    assert Announcer.board_changes(old, new, nil, sync,
             enabled: [:question, :blocked, :ready],
             needs: needs
           ) == []
  end

  test "a newly appearing task and a repeated state stay silent" do
    old = board()
    new = board([task(1, "A", :blocked)])
    assert Announcer.board_changes(old, new, nil, nil, enabled: [:blocked]) == []
    assert Announcer.board_changes(new, new, nil, nil, enabled: [:blocked]) == []
  end

  test "one update is capped at two phrases and one utterance" do
    old = board(for id <- 1..3, do: task(id, "Task #{id}", :running))
    new = board(for id <- 1..3, do: task(id, "Task #{id}", :question))
    texts = Announcer.board_changes(old, new, nil, nil, enabled: [:question], turn: 2)
    assert length(texts) == 2
    assert Announcer.utterance(texts) == Enum.join(texts, " ")
    assert Announcer.utterance([]) == nil
  end
end
