defmodule AgentBoard.Repo.Migrations.CreateSuperagents do
  use Ecto.Migration

  # Project and agent registrations belong to the operator, never to a migration.
  def up do
    create table(:superagents) do
      add :repository_id, references(:repositories, on_delete: :delete_all), null: false
      add :profile, :string, null: false
      add :port, :integer, null: false
      add :state_dir, :string, null: false
      add :desired_state, :string, null: false, default: "running"
      add :observed_state, :string, null: false, default: "unknown"
      add :observed_at, :utc_datetime
      add :last_error, :text
      add :max_workers, :integer, null: false, default: 3
      add :poll_seconds, :integer, null: false, default: 60
      add :created_by, :string, null: false, default: "owner"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:superagents, [:repository_id])
    create unique_index(:superagents, [:profile])
    create unique_index(:superagents, [:port])
    create index(:superagents, [:desired_state, :observed_state])

    create table(:superagent_events) do
      add :superagent_id, references(:superagents, on_delete: :delete_all), null: false
      add :action, :string, null: false
      add :from_state, :string
      add :to_state, :string
      add :actor, :string, null: false
      add :detail, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:superagent_events, [:superagent_id, :inserted_at])
  end

  def down do
    drop table(:superagent_events)
    drop table(:superagents)
  end
end
