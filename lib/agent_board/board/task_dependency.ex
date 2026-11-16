defmodule AgentBoard.Board.TaskDependency do
  @moduledoc "One edge of a split's graph: `task` waits for `blocked_by`."
  use Ecto.Schema

  import Ecto.Query, only: [from: 2]

  schema "task_dependencies" do
    belongs_to :task, AgentBoard.Board.Task
    belongs_to :blocked_by, AgentBoard.Board.Task, foreign_key: :blocked_by_task_id

    timestamps(type: :utc_datetime)
  end

  @doc "States in which a task no longer blocks its dependents, whether merged or just closed."
  @spec resolved_blocker_states() :: [String.t()]
  def resolved_blocker_states, do: ~w(done closed)

  @doc "Edges whose blocking task is unresolved; use the :blocker binding to read that task."
  @spec with_open_blocker() :: Ecto.Query.t()
  def with_open_blocker do
    from d in __MODULE__,
      join: b in assoc(d, :blocked_by),
      as: :blocker,
      where: b.state not in ^resolved_blocker_states()
  end
end
