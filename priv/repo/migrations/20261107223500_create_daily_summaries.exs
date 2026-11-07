defmodule AgentBoard.Repo.Migrations.CreateDailySummaries do
  use Ecto.Migration

  # One row per local day: the summary of the day the board generated after
  # the configured hour. The unique local date is what makes it go out once,
  # across a sleeping Mac, repeated ticks, restarts and two boards on the
  # same database. The content is the facts as observed when it went out.
  def change do
    create table(:daily_summaries) do
      add :local_date, :date, null: false
      add :generated_at, :utc_datetime, null: false
      add :window_start, :utc_datetime, null: false
      add :window_end, :utc_datetime, null: false
      add :content, :map, null: false
      add :spoken_at, :utc_datetime
      add :dismissed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:daily_summaries, [:local_date])
  end
end
