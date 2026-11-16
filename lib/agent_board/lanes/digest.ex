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
end
