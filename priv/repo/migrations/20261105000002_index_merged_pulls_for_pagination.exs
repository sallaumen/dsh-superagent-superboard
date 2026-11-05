defmodule AgentBoard.Repo.Migrations.IndexMergedPullsForPagination do
  use Ecto.Migration

  def change do
    execute(
      "CREATE INDEX pull_requests_merged_page_idx ON pull_requests " <>
        "(repository_id, merged_at DESC NULLS LAST, id DESC) WHERE state = 'merged'",
      "DROP INDEX pull_requests_merged_page_idx"
    )
  end
end
