defmodule AgentBoard.Announcer do
  @moduledoc """
  What the agent should say when the board changes, as a pure diff.

  The LiveView compares the previous and the current board on every
  `:board_updated` and speaks the result in one utterance (two pushes in a
  row would cut the first one off). Two kinds of news:

    * **attention** - a task entered a lane that needs the owner (a
      question, a block, a review), or a running task went silent (a
      `:stalled` item in the needs list, derived, so it is diffed by item,
      not by lane). These come first and rotate through a pool of phrases,
      so the call does not sound like a broken record.
    * **events** - a task started or went back to the queue, and sync
      outcomes getting worse. A task entering `retrying` (a transient
      failure the board retries by itself) is silent.

  A burst is capped; user actions speak their own confirmations, so they
  are not announced here. Nothing here touches the network.
  """

  alias AgentBoard.Voice.Phrases

  @live_states [:running, :retrying, :question, :ready, :blocked, :queued]
  @max_per_update 2

  @doc """
  The texts to speak for a board change, at most `@max_per_update` items,
  attention calls first.

  The boards are the column maps (`%{running: [...], ready: [...]}`) and
  the syncs are the latest `sync`/`sync_error` events, or nil.

  Options: `:language` (default `Phrases.default_language/0`), `:turn`
  (rotates the phrase pools, default 0), `:attention` and `:events`
  (booleans, default true) to silence either kind, and `:needs` (`{old,
  new}` attention lists from `Lanes.needs/3`) for the silences.
  """
  def board_changes(old_board, new_board, old_sync, new_sync, opts \\ []) do
    lang = Keyword.get(opts, :language, Phrases.default_language())
    turn = Keyword.get(opts, :turn, 0)
    {attention, moves} = changes(old_board, new_board, Keyword.get(opts, :needs))

    attention = if Keyword.get(opts, :attention, true), do: attention, else: []

    events =
      if Keyword.get(opts, :events, true),
        do: moves ++ sync_changes(old_sync, new_sync),
        else: []

    (attention ++ events)
    |> Enum.take(@max_per_update)
    |> Enum.with_index(turn)
    |> Enum.map(fn {item, i} -> text(item, lang, i) end)
  end

  @doc """
  Whether a board change calls for the owner: a task entered a lane that
  needs them, or a silence appeared in `needs` (`{old, new}`, as in
  `board_changes/5`). The sync outcomes are never a call.
  """
  def attention?(old_board, new_board, needs \\ nil) do
    {attention, _moves} = changes(old_board, new_board, needs)
    attention != []
  end

  @doc "The texts of one update as a single utterance."
  def utterance([]), do: nil
  def utterance(texts), do: Enum.join(texts, " ")

  @doc "A short, speakable form of an answer; long answers are cut at a word."
  def speakable_answer(text, max_bytes \\ 280) when is_binary(text) do
    if byte_size(text) <= max_bytes do
      text
    else
      text
      |> String.slice(0, max_bytes)
      |> String.trim_trailing()
      |> then(&String.replace(&1, ~r/\s+\S*\z/, ""))
    end
  end

  defp text({:attention, kind, title}, lang, turn), do: Phrases.attention(lang, kind, title, turn)
  defp text({:moved, state, title}, lang, turn), do: Phrases.moved(lang, state, title, turn)
  defp text(:sync_failed, lang, _turn), do: Phrases.sync_failed(lang)
  defp text({:sync_errors, n}, lang, _turn), do: Phrases.sync_errors(lang, n)

  # The calls for attention (lanes, then silences) and the plain moves.
  defp changes(old_board, new_board, needs) do
    {attention, moves} = state_changes(old_board, new_board)
    {attention ++ silence_changes(needs), moves}
  end

  # A move between two live lanes is news; appearing, vanishing or moving
  # into the merged history is not (the acting user already heard that).
  defp state_changes(old_board, new_board) do
    old = by_id(old_board)
    new = by_id(new_board)

    changes =
      for {id, {old_state, task}} <- Enum.sort_by(old, &elem(&1, 0)),
          {new_state, _task} = Map.get(new, id, {nil, nil}),
          new_state != old_state,
          old_state in @live_states,
          new_state in @live_states,
          # A failure the board retries by itself needs nobody: quiet. When
          # the retries run out, the move to `blocked` is the news.
          new_state != :retrying do
        if new_state in Phrases.attention_kinds(),
          do: {:attention, new_state, task.title},
          else: {:moved, new_state, task.title}
      end

    Enum.split_with(changes, &match?({:attention, _, _}, &1))
  end

  # A silence or a long run is news when its item first appears, and quiet
  # while it stays.
  defp silence_changes(nil), do: []

  defp silence_changes({old_needs, new_needs}) do
    for kind <- [:stalled, :slow],
        old_keys = for(need <- old_needs, need.kind == kind, into: MapSet.new(), do: need.key),
        need <- new_needs,
        need.kind == kind,
        not MapSet.member?(old_keys, need.key) do
      {:attention, kind, need.title}
    end
  end

  defp by_id(board) do
    Enum.reduce(@live_states, %{}, fn state, acc ->
      Enum.reduce(Map.get(board, state) || [], acc, fn task, acc ->
        Map.put(acc, task.id, {state, task})
      end)
    end)
  end

  # A new sync_error, or a completed sync with more errors than the last
  # one, is news; a clean sync and a repeating failure are silence.
  defp sync_changes(%{kind: "sync_error", id: id}, %{kind: "sync_error", id: id}), do: []

  defp sync_changes(_old, %{kind: "sync_error"}), do: [:sync_failed]

  defp sync_changes(%{kind: "sync", payload: old}, %{kind: "sync", payload: new}) do
    new_errors = errors(new)
    if new_errors > errors(old), do: [{:sync_errors, new_errors}], else: []
  end

  defp sync_changes(_old, _new), do: []

  defp errors(%{"errors" => n}) when is_integer(n), do: n
  defp errors(%{"errors" => n}) when is_binary(n), do: String.to_integer(n)
  defp errors(_payload), do: 0
end
