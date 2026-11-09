defmodule AgentBoard.Repo.Migrations.AddTaskRelease do
  use Ecto.Migration

  # A task that waits for its dependencies opens without calling the agent;
  # `released_at` is claimed once, before the comment that calls it.
  def change do
    alter table(:tasks) do
      add :held, :boolean, null: false, default: false
      add :released_at, :utc_datetime
    end

    create index(:tasks, [:held], where: "held")
  end
end
