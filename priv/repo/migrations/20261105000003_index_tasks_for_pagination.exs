defmodule AgentBoard.Repo.Migrations.IndexTasksForPagination do
  use Ecto.Migration

  def change do
    create index(:tasks, [:repository_id, :state, :updated_at, :id], name: :tasks_active_page_idx)
  end
end
