defmodule AgentBoard.Lanes.Attention do
  @moduledoc "Rules for the board's attention list."

  alias AgentBoard.Lanes.{CallStatus, RunTiming}

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

  @doc "The instant a task began needing attention, used for its age and new-since-visit flag."
  @spec started_at(map(), atom(), map()) :: DateTime.t() | nil
  # A silence is news from the moment it crossed the threshold, not from the
  # last signal: that is when the item appeared, and what "novo" refers to.
  def started_at(task, :stalled, context) do
    RunTiming.silence_at(context.silences[task.number], context.stall_after)
  end

  # The same for a long run: it is news from the minute it passed its limit.
  def started_at(task, :slow, _context), do: RunTiming.slow_at(task)

  def started_at(%{held: true, released_at: at}, :unanswered, _context), do: at

  def started_at(task, :unanswered, context),
    do: CallStatus.unanswered_at(task, context.stall_after)

  def started_at(task, _kind, _context),
    do: task.state_changed_at || task.updated_at || task.inserted_at

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
