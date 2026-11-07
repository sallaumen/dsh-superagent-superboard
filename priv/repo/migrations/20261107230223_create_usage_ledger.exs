defmodule AgentBoard.Repo.Migrations.CreateUsageLedger do
  use Ecto.Migration

  # The usage ledger (maintainer contract, "Usage ledger"): what Claude Code,
  # Codex and the DeepSeek Harness spent, read from their local files by
  # AgentBoard.Usage.Ledger. Observed data with its source; never a bill.
  def change do
    # One row per transcript the ledger read: a file is read again only when
    # its size or modification time changed.
    create table(:usage_files) do
      add :source, :string, null: false
      add :path, :text, null: false
      add :size, :bigint, null: false
      add :mtime, :bigint, null: false
      # Claude Code transcripts only grow: the next read starts here when the
      # bytes before it are unchanged (fingerprint).
      add :offset, :bigint, null: false, default: 0
      add :fingerprint, :bigint
      add :skipped, :integer, null: false, default: 0
      add :error, :text
      add :read_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:usage_files, [:path])

    # One row per model response, for the sources that repeat a message
    # across files (Claude Code) or name one per response (the harness).
    create table(:usage_messages) do
      add :source, :string, null: false
      add :message_id, :text, null: false
      add :execution_id, :text, null: false
      add :at, :utc_datetime_usec, null: false
      add :day, :date, null: false
      add :cwd, :text
      add :git_branch, :text
      add :model, :text
      add :input_tokens, :bigint, null: false, default: 0
      add :output_tokens, :bigint, null: false, default: 0
      add :cache_read_tokens, :bigint, null: false, default: 0
      add :cache_write_tokens, :bigint, null: false, default: 0
    end

    create unique_index(:usage_messages, [:source, :message_id])
    create index(:usage_messages, [:source, :execution_id])

    # The ledger: one row per execution (a Claude Code session, a Codex
    # thread, a harness ticket), UTC day, cwd, branch and model.
    create table(:usage_ledger) do
      add :source, :string, null: false
      add :execution_id, :text, null: false
      add :day, :date, null: false
      add :cwd, :text
      add :git_branch, :text
      add :model, :text
      add :requests, :integer, null: false, default: 0
      add :input_tokens, :bigint, null: false, default: 0
      add :output_tokens, :bigint, null: false, default: 0
      add :cache_read_tokens, :bigint, null: false, default: 0
      add :cache_write_tokens, :bigint, null: false, default: 0
      add :first_at, :utc_datetime_usec, null: false
      add :last_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:usage_ledger, [:source, :execution_id, :day, :cwd, :git_branch, :model],
             nulls_distinct: false
           )

    create index(:usage_ledger, [:day, :source])

    # The last quota reading per plan limit (Codex's rate_limits).
    create table(:usage_limits) do
      add :source, :string, null: false
      add :limit_id, :string
      add :plan_type, :string
      add :primary_used_percent, :float
      add :primary_window_minutes, :integer
      add :primary_resets_at, :utc_datetime
      add :secondary_used_percent, :float
      add :secondary_window_minutes, :integer
      add :secondary_resets_at, :utc_datetime
      add :has_credits, :boolean
      add :unlimited, :boolean
      add :credits_balance, :string
      add :reached, :string
      add :execution_id, :text
      add :observed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:usage_limits, [:source, :limit_id], nulls_distinct: false)
  end
end
