defmodule AgentBoard.Repo.Migrations.CreateCommits do
  @moduledoc """
  The commits the sync saw on a repository's default branch, so the board can
  count them per hour. A commit stays once seen: the table is a record of what
  the branch carried, not a mirror of its current history.
  """
  use Ecto.Migration

  def change do
    create table(:commits) do
      add :repository_id, references(:repositories, on_delete: :delete_all), null: false
      add :sha, :string, null: false
      add :author, :string
      add :message, :string
      add :authored_at, :utc_datetime
      add :committed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:commits, [:repository_id, :sha])
    create index(:commits, [:repository_id, :committed_at])
  end
end
