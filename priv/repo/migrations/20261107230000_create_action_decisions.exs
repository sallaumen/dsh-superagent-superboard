defmodule AgentBoard.Repo.Migrations.CreateActionDecisions do
  use Ecto.Migration

  # One row per decision `AgentBoard.Actions` took about a write: confirmed
  # by a person, refused (by the gate or by the person) or automatic. The
  # row of an executed decision is written before the effect and gets its
  # outcome after, so a crash in the middle still leaves the decision.
  def change do
    create table(:action_decisions) do
      add :action, :string, null: false
      add :risk, :string, null: false
      add :decision, :string, null: false
      add :by, :string, null: false
      add :via, :string, null: false
      add :evidence, :string
      add :phrase, :text
      add :words, :text
      add :subject, :string
      add :repository_id, references(:repositories, on_delete: :nilify_all)
      add :outcome, :string
      add :detail, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:action_decisions, [:inserted_at])
    create index(:action_decisions, [:action, :inserted_at])
    create index(:action_decisions, [:repository_id])
  end
end
