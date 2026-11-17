defmodule AgentBoard.Lanes.Queue.Detail do
  @moduledoc "Explain what a queued task is waiting for using only the evidence already on the board."

  use Gettext, backend: AgentBoardWeb.Gettext

  alias AgentBoard.Lanes.CallStatus
  alias AgentBoard.{Release, Time}

  @doc "An ordinary hold explains the wait; a call problem keeps its warning alongside any relationship."
  @spec describe(map(), {:unblocks | :split_from, integer()} | nil, [integer()], map()) :: %{
          sub: String.t() | nil,
          stuck: String.t() | nil
        }
  def describe(row, relationship, open_numbers, calls) do
    problem = CallStatus.problem(row, calls)
    stuck = stuck(problem, row, calls)

    sub =
      if CallStatus.dependency_wait?(row.held, problem) do
        waiting_for(open_numbers)
      else
        join(relationship_label(relationship), call_sub(row, calls))
      end

    %{sub: sub, stuck: stuck}
  end

  defp waiting_for([]), do: gettext("waiting for its dependencies")

  defp waiting_for(numbers),
    do: gettext("waiting for %{tasks}", tasks: Enum.map_join(numbers, ", ", &"##{&1}"))

  defp relationship_label({:unblocks, number}), do: gettext("unblocks #%{number}", number: number)

  defp relationship_label({:split_from, number}),
    do: gettext("split from #%{number}", number: number)

  defp relationship_label(nil), do: nil

  defp join(nil, call), do: call
  defp join(relationship, nil), do: relationship
  defp join(relationship, call), do: relationship <> " · " <> call

  # A called task between the call and the start: who holds it now. One
  # nobody answered says so in `stuck/2`; a ticket that started or ended is
  # the overlay's to place (`AgentBoard.Tickets.state/2`).
  defp call_sub(row, calls) do
    case CallStatus.queue_stage(row, calls) do
      {:awaiting_ticket, at} ->
        gettext("called %{ago}, waiting for the agent",
          ago: Time.ago(DateTime.diff(calls.now, at))
        )

      {:in_runner_queue, nil} ->
        gettext("in the agent's queue")

      {:in_runner_queue, at} ->
        gettext("entered the agent's queue %{ago}", ago: Time.ago(DateTime.diff(calls.now, at)))

      nil ->
        nil
    end
  end

  defp stuck(problem, row, calls) do
    case problem do
      :failed ->
        gettext("the call to the agent did not complete")

      :unanswered ->
        called = Time.ago(DateTime.diff(calls.now, Release.called_at(row)))
        gettext("called %{ago}, the agent did not start", ago: called)

      nil ->
        nil
    end
  end
end
