defmodule AgentBoard.Repo.Migrations.AddRuntimeSyncToSuperagents do
  use Ecto.Migration

  def change do
    alter table(:superagents) do
      add :runtime_sync, :map
    end
  end
end
