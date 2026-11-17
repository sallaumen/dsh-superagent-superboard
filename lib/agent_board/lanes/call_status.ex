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

  @doc "The problem the queue and the attention list can report for this call, if any."
  @spec problem(map(), map()) :: :failed | :unanswered | nil
  def problem(task, calls) do
    cond do
      failed?(task, calls.now) -> :failed
      unanswered?(task, calls) -> :unanswered
      true -> nil
    end
  end

  @doc "A held task names its dependencies only while no call problem takes precedence."
  @spec dependency_wait?(boolean(), :failed | :unanswered | nil) :: boolean()
  def dependency_wait?(held, problem), do: held and is_nil(problem)

  @doc "An active ticket can wait in the runner queue only while no start or end was observed."
  @spec pending_ticket?(map()) :: boolean()
  def pending_ticket?(ticket) do
    if ticket["stopped"] || ticket["archived"] do
      false
    else
      is_nil(ticket["started_at"]) and is_nil(ticket["ended_at"])
    end
  end

  @doc "Queue evidence to display before the runner starts, or nil when another lane explains the task."
  @spec queue_stage(map(), map()) ::
          {:awaiting_ticket, DateTime.t()} | {:in_runner_queue, DateTime.t() | nil} | nil
  def queue_stage(task, calls) do
    called = Release.called_at(task)
    ticket = Map.get(calls.tickets, task.number)

    cond do
      is_nil(called) or unanswered?(task, calls) ->
        nil

      is_nil(ticket) ->
        {:awaiting_ticket, called}

      pending_ticket?(ticket) ->
        {:in_runner_queue, last_assignment_at(ticket)}

      true ->
        nil
    end
  end

  defp last_assignment_at(ticket) do
    case List.last(ticket["assignments"] || []) do
      %{"created_at" => %DateTime{} = at} -> at
      _ -> nil
    end
  end
end
