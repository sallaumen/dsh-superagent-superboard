defmodule AgentBoard.Announcer do
  @moduledoc """
  What the agent should say when the board changes, as a pure diff.

  The LiveView compares the previous and the current board on every
  `:board_updated` and pushes the texts here to the agent's voice; nothing
  here touches the network. A burst is capped, and only what the owner
  needs to hear is spoken: task overlays moving between the live lanes and
  sync outcomes getting worse. User actions speak their own confirmations,
  so they are not announced here.
  """

  @live_states [:running, :ready, :blocked, :queued]
  @max_per_update 2

  @doc """
  The texts to speak for a board change, at most `@max_per_update` items.

  The boards are the column maps (`%{running: [...], ready: [...]}`) and
  the syncs are the latest `sync`/`sync_error` events, or nil.
  """
  def board_changes(old_board, new_board, old_sync, new_sync) do
    (state_changes(old_board, new_board) ++ sync_changes(old_sync, new_sync))
    |> Enum.take(@max_per_update)
  end

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

  # A move between two live lanes is news; appearing, vanishing or moving
  # into the merged history is not (the acting user already heard that).
  defp state_changes(old_board, new_board) do
    old = by_id(old_board)
    new = by_id(new_board)

    for {id, {old_state, task}} <- Enum.sort_by(old, &elem(&1, 0)),
        {new_state, _task} = Map.get(new, id, {nil, nil}),
        new_state != old_state,
        old_state in @live_states,
        new_state in @live_states do
      "Task '#{task.title}' is now #{new_state}."
    end
  end

  defp by_id(board) do
    Enum.reduce(@live_states, %{}, fn state, acc ->
      Enum.reduce(Map.get(board, state, []), acc, fn task, acc ->
        Map.put(acc, task.id, {state, task})
      end)
    end)
  end

  # A new sync_error, or a completed sync with more errors than the last
  # one, is news; a clean sync and a repeating failure are silence.
  defp sync_changes(%{kind: "sync_error", id: id}, %{kind: "sync_error", id: id}), do: []

  defp sync_changes(_old, %{kind: "sync_error"}), do: ["The sync failed. Showing saved data."]

  defp sync_changes(%{kind: "sync", payload: old}, %{kind: "sync", payload: new}) do
    new_errors = errors(new)

    if new_errors > errors(old),
      do: ["The sync finished with #{new_errors} error#{if new_errors == 1, do: "", else: "s"}."],
      else: []
  end

  defp sync_changes(_old, _new), do: []

  defp errors(%{"errors" => n}) when is_integer(n), do: n
  defp errors(%{"errors" => n}) when is_binary(n), do: String.to_integer(n)
  defp errors(_payload), do: 0
end
