defmodule AgentBoard.Repo.Migrations.CreateVoiceTurns do
  @moduledoc """
  The owner's spoken conversation with the board's agent: one row per turn
  (`owner`, `agent`) plus `summary` rows that compress the older turns, so
  the conversation keeps its whole context without sending every word to the
  model. An agent turn may carry a proposal (a write waiting for a spoken
  yes); `proposal_status` is its lifecycle.
  """
  use Ecto.Migration

  def change do
    create table(:voice_turns) do
      add :role, :string, null: false
      add :text, :text, null: false
      add :repository_id, references(:repositories, on_delete: :nilify_all)
      add :action, :string
      add :proposal, :map
      add :proposal_status, :string
      add :summary_through_id, :bigint
      timestamps(type: :utc_datetime_usec)
    end

    create index(:voice_turns, [:role, :id])
    create index(:voice_turns, [:proposal_status])
  end
end
