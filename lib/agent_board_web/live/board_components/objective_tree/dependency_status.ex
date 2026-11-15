defmodule AgentBoardWeb.BoardComponents.ObjectiveTree.DependencyStatus do
  @moduledoc "The dependency status to describe for a node in the objective tree."

  alias AgentBoard.Board.TaskDependency

  @type t ::
          :call_failed
          | :no_dependency
          | :finished
          | :starting_soon
          | :ready_to_start
          | :dependencies_finished
          | {:waiting_for | :depends_on_open, [integer()]}

  @doc "Classifies a node, keeping open blockers in their display order."
  @spec classify(map()) :: t()
  def classify(%{held: true, released_at: %DateTime{}}), do: :call_failed
  def classify(%{waiting: []}), do: :no_dependency
  def classify(%{state: state}) when state in ~w(done closed), do: :finished

  def classify(%{waiting: waiting} = node) do
    resolved = TaskDependency.resolved_blocker_states()
    open = for blocker <- waiting, blocker.state not in resolved, do: blocker.number

    case {open, node} do
      {[], %{held: true}} -> :starting_soon
      {[], %{state: "queued"}} -> :ready_to_start
      {[], _} -> :dependencies_finished
      {numbers, %{held: true}} -> {:waiting_for, numbers}
      {numbers, _} -> {:depends_on_open, numbers}
    end
  end
end
