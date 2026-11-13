defmodule AgentBoard.Repo.Migrations.AddGithubReopenedAt do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :github_reopened_at, :utc_datetime
    end
  end
end
