defmodule AgentBoard.Repo.Migrations.AddProvisionRetryToSuperagents do
  use Ecto.Migration

  def change do
    alter table(:superagents) do
      add :checkout_path, :string
      add :source_profile, :string
      add :provision_failed_at, :utc_datetime
    end
  end
end
