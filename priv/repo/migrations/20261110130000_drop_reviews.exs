defmodule AgentBoard.Repo.Migrations.DropReviews do
  use Ecto.Migration

  # The sync wrote one row per pull request review here and nothing ever read
  # them: a pull request's review state lives in pull_requests.review_state,
  # from the same GitHub read. The code that wrote the rows left in #500.
  #
  # The rows are not kept. `down` brings back the empty table, so a rollback
  # works, but a board older than #500 on this database fails its sync on the
  # missing table until it is updated.
  def up do
    drop table(:reviews)
  end

  def down do
    create table(:reviews) do
      add :pull_request_id, references(:pull_requests, on_delete: :delete_all), null: false
      add :reviewer, :string, null: false
      add :state, :string, null: false
      add :submitted_at, :utc_datetime
    end

    create unique_index(:reviews, [:pull_request_id, :reviewer, :submitted_at])
  end
end
