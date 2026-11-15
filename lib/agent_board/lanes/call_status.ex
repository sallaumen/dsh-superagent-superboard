defmodule AgentBoard.Lanes.CallStatus do
  @moduledoc "What the queue and attention list can infer from a call to the agent."

  alias AgentBoard.Release

  @call_grace 60

  @doc "A claimed call that is still held after a minute is no longer considered in flight."
  @spec failed?(map(), DateTime.t()) :: boolean()
  def failed?(%{held: true, released_at: %DateTime{} = at}, now),
    do: DateTime.diff(now, at) >= @call_grace

  def failed?(_task, _now), do: false

  @doc "When a call would need attention if there were still no ticket for the issue."
  @spec unanswered_at(map(), integer()) :: DateTime.t() | nil
  def unanswered_at(task, stall_after) do
    case Release.called_at(task) do
      %DateTime{} = at -> DateTime.add(at, stall_after, :second)
      nil -> nil
    end
  end

  @doc "Whether a call crossed its deadline without a ticket naming the issue."
  @spec unanswered?(map(), map()) :: boolean()
  def unanswered?(task, %{tickets: tickets, stall_after: stall_after, now: now}) do
    case Release.called_at(task) do
      %DateTime{} = at ->
        not Map.has_key?(tickets, task.number) and DateTime.diff(now, at) >= stall_after

      nil ->
        false
    end
  end
end
