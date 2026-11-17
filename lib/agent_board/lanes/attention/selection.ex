defmodule AgentBoard.Lanes.Attention.Selection do
  @moduledoc "Select work that needs attention before its reports and display details are read."
  alias AgentBoard.Lanes.{Attention, CallStatus}

  @type candidate ::
          %{kind: :blocked | :review | :question | :stalled | :slow, task: map()}
          | %{kind: :unanswered, task: map(), problem: :failed | :unanswered}

  @doc "Keep input order for sorting ties. A nil waiting count means no outage; zero still shows one."
  @spec plan(map(), map()) :: %{visible: [candidate()], waiting: non_neg_integer() | nil}
  def plan(board, context) do
    candidates = candidates(board, context)

    if context.agent == :down do
      {waiting, visible} =
        Attention.outage_summary(candidates, length(Map.get(board, :retrying, [])))

      %{waiting: waiting, visible: visible}
    else
      %{waiting: nil, visible: candidates}
    end
  end

  @doc "The selected review tasks that need linked PR evidence, in board order."
  @spec review_tasks([candidate()]) :: [map()]
  def review_tasks(visible), do: for(%{kind: :review, task: task} <- visible, do: task)

  defp candidates(board, context) do
    lane(board, :blocked, :blocked) ++
      running_lane(board, context) ++
      unanswered_lane(board, context) ++
      lane(board, :ready, :review) ++ lane(board, :question, :question)
  end

  defp lane(board, key, kind),
    do: for(task <- Map.get(board, key, []), do: %{task: task, kind: kind})

  defp running_lane(board, %{silences: silences, stall_after: stall_after, now: now}) do
    for task <- Map.get(board, :running, []),
        kind = Attention.running_kind(task, silences[task.number], stall_after, now),
        do: %{task: task, kind: kind}
  end

  defp unanswered_lane(board, context) do
    for task <- Map.get(board, :queued, []),
        problem = CallStatus.problem(task, context),
        do: %{kind: :unanswered, task: task, problem: problem}
  end
end
