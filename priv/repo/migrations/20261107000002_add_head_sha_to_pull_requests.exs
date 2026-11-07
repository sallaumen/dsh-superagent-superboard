defmodule AgentBoard.Repo.Migrations.AddHeadShaToPullRequests do
  use Ecto.Migration

  # The sha the local gate in a workpad must match: the PR's head, as the
  # sync last saw it. Nullable: rows synced before this column stay unknown
  # until the next sync.
  def change do
    alter table(:pull_requests) do
      add :head_sha, :string
    end
  end
end
