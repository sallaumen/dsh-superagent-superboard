defmodule AgentBoard.Repo.Migrations.CreateObjectives do
  use Ecto.Migration

  # A group of tasks with one done criterion (docs/research/alfred.md,
  # F3.4). The composer creates one when a split returns more than one task.
  def change do
    create table(:objectives) do
      add :repository_id, references(:repositories, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :done_criterion, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:objectives, [:repository_id, :inserted_at])

    alter table(:tasks) do
      add :objective_id, references(:objectives, on_delete: :nilify_all)
    end

    create index(:tasks, [:objective_id])
  end
end
