defmodule AgentBoard.Repo.Migrations.CreateSettings do
  @moduledoc "Board-wide settings, one row per key. The UI writes; the code reads."
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :string
      timestamps(type: :utc_datetime, updated_at: false)
    end
  end
end
