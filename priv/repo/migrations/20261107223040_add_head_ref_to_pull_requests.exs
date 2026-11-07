defmodule AgentBoard.Repo.Migrations.AddHeadRefToPullRequests do
  use Ecto.Migration

  # What ties a session to a task through its PR (docs/research/alfred.md,
  # 3.4): the PR's branch (`head.ref`) and the issues its body closes
  # (`Closes #n`), both written by the sync from the pull it already fetches.
  # `head_ref` is nullable: a row synced before this column stays unknown
  # until the next sync, and a fork's branch is not a branch of this
  # repository. `closes_issues` keeps the order the body names them.
  def change do
    alter table(:pull_requests) do
      add :head_ref, :string
      add :closes_issues, {:array, :integer}, null: false, default: []
    end

    create index(:pull_requests, [:repository_id, :head_ref])
  end
end
