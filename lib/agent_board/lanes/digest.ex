defmodule AgentBoard.Lanes.Digest do
  @moduledoc "The facts the board can state in its visit digest."

  alias AgentBoard.Board

  @doc "Nonempty first-visit counts in reading order. Reviews and questions both wait on the owner."
  @spec first_visit(map()) :: [{atom(), pos_integer()}]
  def first_visit(board) do
    [
      running: Board.lane_count(board, :running),
      retrying: Board.lane_count(board, :retrying),
      waiting: Board.lane_count(board, :ready) + Board.lane_count(board, :question),
      blocked: Board.lane_count(board, :blocked),
      queued: Board.lane_count(board, :queued)
    ]
    |> Enum.filter(fn {_kind, n} -> n > 0 end)
  end

  @doc "Name a task only when the lane total is one and its single row is available."
  @spec task_subject(map(), atom()) :: {:task, integer(), integer()} | pos_integer() | nil
  def task_subject(board, lane) do
    case {Board.lane_count(board, lane), Map.get(board, lane, [])} do
      {1, [task]} -> {:task, task.id, task.number}
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end
end
