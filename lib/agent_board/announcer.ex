defmodule AgentBoard.Announcer do
  @moduledoc """
  A quiet, pure diff for the few board changes worth an optional spoken call.

  Progress, queue movement, synchronization and derived slow/stalled timers
  stay visible on the board. They never produce automatic speech.
  """

  alias AgentBoard.Voice.Phrases

  @live_states [:running, :retrying, :question, :ready, :blocked, :queued]
  @max_per_update 2

  @doc """
  At most two enabled calls for tasks newly entering question, block or review.
  A task first appearing in a lane is not a transition and stays silent.
  """
  def board_changes(old_board, new_board, _old_sync, _new_sync, opts \\ []) do
    lang = Keyword.get(opts, :language, Phrases.default_language())
    turn = Keyword.get(opts, :turn, 0)
    enabled = Keyword.get(opts, :enabled, [])
    old = by_id(old_board)

    new_board
    |> by_id()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(&new_call(&1, old, enabled))
    |> Enum.take(@max_per_update)
    |> Enum.with_index(turn)
    |> Enum.map(fn {{state, title}, i} -> Phrases.attention(lang, state, title, i) end)
  end

  @doc "The texts of one update as a single utterance."
  def utterance([]), do: nil
  def utterance(texts), do: Enum.join(texts, " ")

  defp new_call({id, {state, task}}, old, enabled) do
    case Map.get(old, id) do
      {old_state, _} when old_state != state and state in [:question, :blocked, :ready] ->
        if state in enabled, do: [{state, task.title}], else: []

      _ ->
        []
    end
  end

  defp by_id(board) do
    Enum.reduce(@live_states, %{}, fn state, acc ->
      Enum.reduce(Map.get(board, state) || [], acc, fn task, acc ->
        Map.put(acc, task.id, {state, task})
      end)
    end)
  end
end
