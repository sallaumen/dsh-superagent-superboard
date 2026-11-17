defmodule AgentBoard.Repo.Migrations.AddPullReportedEvidence do
  use Ecto.Migration

  def change do
    alter table(:pull_requests) do
      add :reported_evidence, :map, default: %{}, null: false
      add :evidence_source_updated_at, :utc_datetime
      add :evidence_refresh_at, :utc_datetime
    end

    # One recent PR per normal sync cycle, including rows settled before upgrade.
    execute(
      "UPDATE pull_requests SET evidence_refresh_at = NOW() WHERE state = 'open' OR merged_at >= NOW() - INTERVAL '30 days'",
      "SELECT 1"
    )
  end
end
