defmodule AgentBoard.Runners.Execution do
  @moduledoc """
  One dispatch to a local runner: the task, the executor, the session id,
  the worktree and the run directory whose status file the board observes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(starting running done failed stopped)

  schema "runner_executions" do
    field :executor, :string
    field :status, :string, default: "starting"
    field :session_id, :string
    field :decision_id, :integer
    field :run_dir, :string
    field :worktree, :string
    field :branch, :string
    field :model, :string
    field :ceiling_micros, :integer
    field :timeout_seconds, :integer
    field :result, :string
    field :error, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    belongs_to :task, AgentBoard.Board.Task
    belongs_to :repository, AgentBoard.Board.Repository

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(execution, attrs) do
    execution
    |> cast(attrs, [
      :task_id,
      :repository_id,
      :executor,
      :status,
      :session_id,
      :decision_id,
      :run_dir,
      :worktree,
      :branch,
      :model,
      :ceiling_micros,
      :timeout_seconds,
      :result,
      :error,
      :started_at,
      :finished_at
    ])
    |> validate_required([:task_id, :repository_id, :executor, :run_dir])
    |> validate_inclusion(:executor, ~w(claude codex))
    |> validate_inclusion(:status, @statuses)
  end

  def statuses, do: @statuses
end
