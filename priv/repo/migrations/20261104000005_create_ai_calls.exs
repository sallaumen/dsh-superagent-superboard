defmodule AgentBoard.Repo.Migrations.CreateAiCalls do
  @moduledoc "One row per model call: what was asked, what it cost, how long."
  use Ecto.Migration

  def change do
    create table(:ai_calls) do
      add :name, :string, null: false
      add :engine, :string, null: false
      add :model, :string
      add :tier, :string
      add :status, :string, null: false
      add :input_tokens, :integer, default: 0
      add :output_tokens, :integer, default: 0
      add :cost_micros, :integer, default: 0
      add :duration_ms, :integer, default: 0
      add :parse_state, :string
      add :json, :map
      add :error, :string
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ai_calls, [:inserted_at])
    create index(:ai_calls, [:name])
  end
end
