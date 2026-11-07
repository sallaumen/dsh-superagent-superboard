defmodule AgentBoard.Repo.Migrations.CreateAgentRetries do
  use Ecto.Migration

  # One row per automatic retry the board asked the runner for, keyed by the
  # Assignment that failed: the unique index is what makes the retry happen
  # at most once per Assignment, across board restarts and two boards on the
  # same database.
  def change do
    create table(:agent_retries) do
      add :ticket_id, :string, null: false
      add :assignment_id, :string, null: false
      add :attempt, :integer, null: false
      add :cause, :string
      add :stage, :string
      add :summary, :text
      add :failed_at, :utc_datetime
      add :outcome, :string, null: false
      add :detail, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:agent_retries, [:assignment_id])
    create index(:agent_retries, [:ticket_id])
  end
end
