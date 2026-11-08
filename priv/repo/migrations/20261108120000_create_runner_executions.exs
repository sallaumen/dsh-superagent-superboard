defmodule AgentBoard.Repo.Migrations.CreateRunnerExecutions do
  use Ecto.Migration

  # One row per dispatch to a local runner (Claude Code or Codex). The
  # process is not a child of the board: the row names the session, the
  # worktree and the run directory the runner writes, and the board only
  # observes them.
  def change do
    create table(:runner_executions) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :repository_id, references(:repositories, on_delete: :delete_all), null: false
      add :executor, :string, null: false
      add :status, :string, null: false, default: "starting"
      add :session_id, :text
      add :decision_id, :integer
      add :run_dir, :text, null: false
      add :worktree, :text
      add :branch, :text
      add :model, :text
      add :ceiling_micros, :bigint
      add :timeout_seconds, :integer
      add :result, :text
      add :error, :text
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:runner_executions, [:task_id, :inserted_at])
    create index(:runner_executions, [:status])

    # One task never has two executions at the same time; a finished one
    # leaves the slot free for a later decision.
    create unique_index(:runner_executions, [:task_id],
             where: "status IN ('starting', 'running')",
             name: :runner_executions_one_active_per_task
           )
  end
end
