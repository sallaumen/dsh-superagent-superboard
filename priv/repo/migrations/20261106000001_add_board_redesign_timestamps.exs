defmodule AgentBoard.Repo.Migrations.AddBoardRedesignTimestamps do
  @moduledoc """
  The redesign needs to know when a state actually changed, not when the sync
  last touched the row. Existing rows stay NULL: an unknown change time is
  honest, while backfilling with `updated_at` would mark everything as new.
  """
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :started_at, :utc_datetime
      add :state_changed_at, :utc_datetime
      add :origin_task_id, references(:tasks, on_delete: :nilify_all)
    end

    create index(:tasks, [:origin_task_id])

    alter table(:pull_requests) do
      add :checks_changed_at, :utc_datetime
    end
  end
end
