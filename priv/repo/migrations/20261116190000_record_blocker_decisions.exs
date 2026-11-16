defmodule AgentBoard.Repo.Migrations.RecordBlockerDecisions do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :github_issue_status, :string
      add :blocker_decision, :map
    end
  end
end
