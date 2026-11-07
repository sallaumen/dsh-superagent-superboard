defmodule AgentBoard.Repo.Migrations.AddWorkTypeAndSizeToTasks do
  use Ecto.Migration

  # What the split (the `:propose_tasks` call) said about a task it created:
  # where the work lands (ui, backend, docs, bug, research, infra) and its
  # size (S, M, L). Nullable: a task from the sync, a single request or a
  # split that did not classify it has no kind and no size.
  def change do
    alter table(:tasks) do
      add :work_type, :string
      add :size, :string
    end
  end
end
