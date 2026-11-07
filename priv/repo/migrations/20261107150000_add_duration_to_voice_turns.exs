defmodule AgentBoard.Repo.Migrations.AddDurationToVoiceTurns do
  @moduledoc "How long the agent took to answer a turn (model and action), for the history view."
  use Ecto.Migration

  def change do
    alter table(:voice_turns) do
      add :duration_ms, :integer
    end
  end
end
