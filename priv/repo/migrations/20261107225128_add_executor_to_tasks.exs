defmodule AgentBoard.Repo.Migrations.AddExecutorToTasks do
  use Ecto.Migration

  # Who a task the board created is for: dsh, claude or codex
  # (AgentBoard.Executors). Nullable: an issue the sync found, or a task
  # created before the choice existed, has no recorded executor.
  def change do
    alter table(:tasks) do
      add :executor, :string
    end
  end
end
