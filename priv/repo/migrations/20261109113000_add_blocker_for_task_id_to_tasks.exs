defmodule AgentBoard.Repo.Migrations.AddBlockerForTaskIdToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :blocker_for_task_id, references(:tasks, on_delete: :nilify_all)
    end

    create index(:tasks, [:blocker_for_task_id])
  end
end
