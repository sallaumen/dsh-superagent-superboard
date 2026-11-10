defmodule AgentBoard.Repo.Migrations.AddCacheWrite1hToUsage do
  use Ecto.Migration

  # Claude Code charges a 1-hour cache write at twice the input price and a
  # 5-minute one at 1.25 times. The ledger held one write count and priced
  # all of it at 1.25, so most sessions showed below Claude Code's own cost.
  # The 1-hour part is part of cache_write_tokens, never added to it.
  #
  # usage_files.reader says which reader read a file. A Claude Code transcript
  # read by an older reader is read once more, in full, to fill the new count
  # (AgentBoard.Usage.Ledger). Existing rows hold 0 until then, which prices
  # them at the 5-minute rate as before.
  def change do
    alter table(:usage_messages) do
      add :cache_write_1h_tokens, :bigint, null: false, default: 0
    end

    alter table(:usage_ledger) do
      add :cache_write_1h_tokens, :bigint, null: false, default: 0
    end

    alter table(:usage_files) do
      add :reader, :integer, null: false, default: 1
    end
  end
end
