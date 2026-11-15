defmodule AgentBoard.Repo.Migrations.RefreshMergedReviewVerdicts do
  use Ecto.Migration

  def change do
    alter table(:pull_requests) do
      add :review_refresh_at, :utc_datetime
    end

    create index(:pull_requests, [:repository_id, :review_refresh_at],
             where: "review_refresh_at IS NOT NULL"
           )

    execute(
      """
      UPDATE pull_requests SET review_refresh_at = timezone('UTC', now())
      WHERE state = 'merged' AND review_state = 'changes_requested'
      """,
      "SELECT 1"
    )
  end
end
