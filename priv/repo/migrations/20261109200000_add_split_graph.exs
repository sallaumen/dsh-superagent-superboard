defmodule AgentBoard.Repo.Migrations.AddSplitGraph do
  use Ecto.Migration

  # What a split decided, kept: who blocks whom, and the request behind an
  # objective with the issue that groups its tasks on GitHub. Only additions:
  # the code before this migration never reads them.
  def change do
    create table(:task_dependencies) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :blocked_by_task_id, references(:tasks, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:task_dependencies, [:task_id, :blocked_by_task_id])
    create index(:task_dependencies, [:blocked_by_task_id])

    alter table(:objectives) do
      add :request_key, :string
      add :request_text, :text
      add :spec, :map
      add :issue_number, :integer
      add :issue_url, :string
    end

    create unique_index(:objectives, [:repository_id, :request_key])
  end
end
