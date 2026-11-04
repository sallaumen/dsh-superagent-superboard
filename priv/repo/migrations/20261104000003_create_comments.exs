defmodule AgentBoard.Repo.Migrations.CreateComments do
  @moduledoc "The conversation: the comments on a task's issue, from the user and the agent."
  use Ecto.Migration

  def change do
    create table(:comments) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :github_id, :bigint
      add :author, :string
      add :body, :text
      add :kind, :string, default: "user", null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:comments, [:task_id, :github_id])
    create index(:comments, [:task_id, :inserted_at])
  end
end
