defmodule AgentBoard.Repo.Migrations.AddAiCacheHash do
  @moduledoc "The call's input fingerprint, so an identical call can be served from a row."
  use Ecto.Migration

  def change do
    alter table(:ai_calls) do
      add :input_hash, :string
    end

    create index(:ai_calls, [:input_hash, :inserted_at])
  end
end
