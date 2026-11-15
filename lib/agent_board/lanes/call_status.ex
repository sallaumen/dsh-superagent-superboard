defmodule AgentBoard.Lanes.CallStatus do
  @moduledoc "What the queue and attention list can infer from a call to the agent."

  @call_grace 60

  @doc "A claimed call that is still held after a minute is no longer considered in flight."
  @spec failed?(map(), DateTime.t()) :: boolean()
  def failed?(%{held: true, released_at: %DateTime{} = at}, now),
    do: DateTime.diff(now, at) >= @call_grace

  def failed?(_task, _now), do: false
end
