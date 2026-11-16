defmodule AgentBoard.Lanes.Attention do
  @moduledoc "Rules for the board's attention list."

  @doc "Sort by priority, then new before seen, then oldest first. Exact ties retain input order."
  @spec sort([map()]) :: [map()]
  def sort(needs) do
    Enum.sort_by(needs, fn need ->
      {rank(need.kind), not need.is_new, -(need.age_seconds || 0)}
    end)
  end

  @doc "Count items explained by the outage, including pending retries, and keep independent needs."
  @spec outage_summary([map()], non_neg_integer()) :: {non_neg_integer(), [map()]}
  def outage_summary(needs, retrying_count) do
    {waiting, rest} =
      Enum.split_with(needs, &(&1.kind in [:blocked, :stalled, :unanswered, :slow]))

    {length(waiting) + retrying_count, rest}
  end

  # A silent run blocks the whole queue while there is one worker: it comes
  # right after a block, before the work that only waits for the owner.
  # The agent being down explains every block and silence below it.
  defp rank(:agent_down), do: -1
  defp rank(:cifail), do: 0
  defp rank(:blocked), do: 1
  defp rank(:stalled), do: 2
  defp rank(:unanswered), do: 2
  defp rank(:review), do: 3
  defp rank(:question), do: 4
  # Nothing to do yet: after everything that waits for the owner.
  defp rank(:slow), do: 5
end
