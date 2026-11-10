defmodule AgentBoard.AnnouncerTest do
  @moduledoc "What the agent says when the board changes: the pure diff."
  use ExUnit.Case, async: true

  alias AgentBoard.Announcer
  alias AgentBoard.Voice.Phrases

  defp task(id, title, state), do: %{id: id, title: title, state: state}

  defp board(tasks \\ []) do
    empty = %{running: [], question: [], ready: [], blocked: [], queued: [], merged: []}

    Enum.reduce(tasks, empty, fn t, acc -> Map.update!(acc, t.state, &[t | &1]) end)
  end

  defp sync(kind, errors \\ 0, id \\ 1) do
    %{id: id, kind: kind, payload: %{"errors" => errors}}
  end

  test "a task that starts is spoken in Portuguese by default" do
    old = board([task(1, "Ship it", :queued)])
    new = board([task(1, "Ship it", :running)])

    assert Announcer.board_changes(old, new, nil, nil) == ["Comecei Ship it."]
  end

  test "the language option switches every sentence" do
    old = board([task(1, "Ship it", :queued)])
    new = board([task(1, "Ship it", :running)])

    assert Announcer.board_changes(old, new, nil, nil, language: "en-US") == [
             "I started Ship it."
           ]

    assert Announcer.board_changes(board(), board(), nil, sync("sync_error"), language: "en-US") ==
             ["The sync failed. I'm showing the saved data."]
  end

  test "a task that starts waiting for an answer calls the owner" do
    old = board([task(1, "Ship it", :running)])
    new = board([task(1, "Ship it", :question)])

    assert [text] = Announcer.board_changes(old, new, nil, nil, turn: 0)
    assert text == Phrases.attention("pt-BR", :question, "Ship it", 0)
    assert text =~ "Ship it"
  end

  test "blocked and review are calls for attention too" do
    old = board([task(1, "One", :running), task(2, "Two", :running)])
    new = board([task(1, "One", :blocked), task(2, "Two", :ready)])

    assert Announcer.board_changes(old, new, nil, nil, turn: 3) == [
             Phrases.attention("pt-BR", :blocked, "One", 3),
             Phrases.attention("pt-BR", :ready, "Two", 4)
           ]
  end

  test "a failure the board retries by itself is quiet; running out of retries is the call" do
    retrying = %{board() | running: []} |> Map.put(:retrying, [task(1, "Ship it", :retrying)])

    assert Announcer.board_changes(board([task(1, "Ship it", :running)]), retrying, nil, nil) ==
             []

    assert Announcer.board_changes(retrying, board([task(1, "Ship it", :blocked)]), nil, nil,
             turn: 0
           ) ==
             [Phrases.attention("pt-BR", :blocked, "Ship it", 0)]
  end

  test "a run past its time is said once, when its item first appears" do
    need = %{key: "task-1", kind: :slow, title: "Ship it"}
    silent = %{key: "task-1", kind: :stalled, title: "Ship it"}

    assert Announcer.board_changes(board(), board(), nil, nil, needs: {[], [need]}) ==
             [Phrases.attention("pt-BR", :slow, "Ship it", 0)]

    assert Announcer.board_changes(board(), board(), nil, nil, needs: {[need], [need]}) == []

    # the same task going silent later is other news, said in its own words
    assert Announcer.board_changes(board(), board(), nil, nil, needs: {[need], [silent]}) ==
             [Phrases.attention("pt-BR", :stalled, "Ship it", 0)]
  end

  test "a silence calls the owner once, when its item first appears" do
    need = %{key: "task-1", kind: :stalled, title: "Ship it"}
    review = %{key: "task-2", kind: :review, title: "Other"}

    assert Announcer.board_changes(board(), board(), nil, nil, needs: {[review], [need, review]}) ==
             [Phrases.attention("pt-BR", :stalled, "Ship it", 0)]

    assert Announcer.board_changes(board(), board(), nil, nil, needs: {[need], [need]}) == []

    assert Announcer.board_changes(board(), board(), nil, nil,
             needs: {[], [need]},
             attention: false
           ) == []
  end

  test "the turn rotates the phrase, so the same call is not repeated" do
    old = board([task(1, "Ship it", :running)])
    new = board([task(1, "Ship it", :question)])

    texts =
      for turn <- 0..9, do: hd(Announcer.board_changes(old, new, nil, nil, turn: turn))

    assert length(Enum.uniq(texts)) == 10
  end

  test "attention comes before the other news and survives the cap" do
    old =
      board([task(1, "A", :queued), task(2, "B", :queued), task(3, "C", :running)])

    new =
      board([task(1, "A", :running), task(2, "B", :running), task(3, "C", :question)])

    assert [first, second] = Announcer.board_changes(old, new, nil, nil, turn: 0)
    assert first == Phrases.attention("pt-BR", :question, "C", 0)
    assert second =~ "A"
  end

  test "each kind can be silenced on its own" do
    old = board([task(1, "A", :queued), task(2, "B", :running)])
    new = board([task(1, "A", :running), task(2, "B", :blocked)])

    assert [only] = Announcer.board_changes(old, new, nil, nil, events: false)
    assert only == Phrases.attention("pt-BR", :blocked, "B", 0)

    assert Announcer.board_changes(old, new, nil, nil, attention: false) == ["Comecei A."]
  end

  test "a task that appears is not announced" do
    assert Announcer.board_changes(board([]), board([task(1, "Ship it", :queued)]), nil, nil) ==
             []
  end

  test "a task moving into the merged history is not announced" do
    old = board([task(1, "Ship it", :queued)])
    new = board([task(1, "Ship it", :merged)])

    assert Announcer.board_changes(old, new, nil, nil) == []
  end

  test "a new sync failure is announced once" do
    assert Announcer.board_changes(board([]), board([]), nil, sync("sync_error")) ==
             ["A sincronização falhou. Estou mostrando os dados salvos."]

    # The same failure keeps repeating every minute: silence.
    assert Announcer.board_changes(board([]), board([]), sync("sync_error"), sync("sync_error")) ==
             []
  end

  test "more errors than the last sync are announced, a clean sync is not" do
    assert Announcer.board_changes(board([]), board([]), sync("sync", 0), sync("sync", 2)) ==
             ["A sincronização terminou com 2 erros."]

    assert Announcer.board_changes(board([]), board([]), sync("sync", 0), sync("sync", 1)) ==
             ["A sincronização terminou com 1 erro."]

    assert Announcer.board_changes(board([]), board([]), sync("sync", 2), sync("sync", 0)) == []
  end

  test "a burst is capped and spoken as one utterance" do
    old = board([task(1, "One", :queued), task(2, "Two", :queued), task(3, "Three", :queued)])
    new = board([task(1, "One", :running), task(2, "Two", :running), task(3, "Three", :running)])

    changes = Announcer.board_changes(old, new, nil, nil)
    assert length(changes) == 2
    assert Announcer.utterance(changes) == Enum.join(changes, " ")
    assert Announcer.utterance([]) == nil
  end

  test "a long answer is cut at a word boundary" do
    long = String.duplicate("word ", 100)

    assert byte_size(Announcer.speakable_answer(long, 40)) <= 40
    refute Announcer.speakable_answer(long, 40) =~ ~r/\s+\z/

    short = "All clear."
    assert Announcer.speakable_answer(short) == short
  end
end
