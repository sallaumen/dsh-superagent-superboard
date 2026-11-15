defmodule AgentBoard.Board.TaskDependency do
  @moduledoc "One edge of a split's graph: `task` waits for `blocked_by`."
  use Ecto.Schema

  schema "task_dependencies" do
    belongs_to :task, AgentBoard.Board.Task
    belongs_to :blocked_by, AgentBoard.Board.Task, foreign_key: :blocked_by_task_id

    timestamps(type: :utc_datetime)
  end

  @doc "States in which a task no longer blocks its dependents, whether merged or just closed."
  @spec resolved_blocker_states() :: [String.t()]
  def resolved_blocker_states, do: ~w(done closed)
end
