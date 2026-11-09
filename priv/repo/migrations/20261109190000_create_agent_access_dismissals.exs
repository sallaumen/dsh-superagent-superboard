defmodule AgentBoard.Repo.Migrations.CreateAgentAccessDismissals do
  use Ecto.Migration

  def change do
    create table(:agent_access_dismissals) do
      add :superagent_id, references(:superagents, on_delete: :delete_all), null: false
      add :login, :string, null: false
      add :dismissed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agent_access_dismissals, [:superagent_id, :login])
  end
end
