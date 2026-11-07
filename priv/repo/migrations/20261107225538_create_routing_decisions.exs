defmodule AgentBoard.Repo.Migrations.CreateRoutingDecisions do
  use Ecto.Migration

  # One row per task the board created: what the router suggested, what the
  # owner chose, why, and the signals it read (docs/research/alfred.md, 3.5).
  # The base of the measurement: acceptance rate and, on a change, the
  # chosen executor's result against the suggested one's.
  def change do
    create table(:routing_decisions) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :suggested, :string
      add :chosen, :string, null: false
      add :mode, :string, null: false
      add :reasons, {:array, :string}, null: false, default: []
      add :alternatives, {:array, :string}, null: false, default: []
      add :signals, :map, null: false, default: %{}
      add :decided_by, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:routing_decisions, [:task_id])
  end
end
