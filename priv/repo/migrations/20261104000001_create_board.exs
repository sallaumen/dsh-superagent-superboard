defmodule AgentBoard.Repo.Migrations.CreateBoard do
  @moduledoc """
  The board's data model: repositories, tasks, pull requests, reviews, events
  and sync runs.
  """
  use Ecto.Migration

  def change do
    create table(:repositories) do
      add :owner, :string, null: false
      add :name, :string, null: false
      add :active, :boolean, default: true, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:repositories, [:owner, :name])

    create table(:tasks) do
      add :repository_id, references(:repositories, on_delete: :delete_all), null: false
      add :kind, :string, default: "issue", null: false
      add :number, :integer
      add :title, :string, null: false
      add :body, :text
      add :state, :string, default: "queued", null: false
      add :url, :string
      add :author, :string
      add :stopped, :boolean, default: false, null: false
      add :archived, :boolean, default: false, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:tasks, [:repository_id, :kind, :number])
    create index(:tasks, [:repository_id, :state])

    create table(:pull_requests) do
      add :repository_id, references(:repositories, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      add :title, :string, null: false
      add :state, :string, null: false
      add :url, :string
      add :author, :string
      add :opened_at, :utc_datetime
      add :merged_at, :utc_datetime
      add :review_state, :string
      add :checks_state, :string
      add :checks_failed, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:pull_requests, [:repository_id, :number])

    create table(:reviews) do
      add :pull_request_id, references(:pull_requests, on_delete: :delete_all), null: false
      add :reviewer, :string, null: false
      add :state, :string, null: false
      add :submitted_at, :utc_datetime
    end

    create unique_index(:reviews, [:pull_request_id, :reviewer, :submitted_at])

    create table(:events) do
      add :repository_id, references(:repositories, on_delete: :delete_all)
      add :kind, :string, null: false
      add :subject, :string
      add :payload, :map
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:events, [:repository_id, :inserted_at])

    create table(:sync_runs) do
      add :repository_id, references(:repositories, on_delete: :delete_all), null: false
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :ok, :boolean
      add :detail, :string
    end
  end
end
