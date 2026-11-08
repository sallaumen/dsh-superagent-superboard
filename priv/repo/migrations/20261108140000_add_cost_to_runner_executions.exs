defmodule AgentBoard.Repo.Migrations.AddCostToRunnerExecutions do
  use Ecto.Migration

  # The CLI's own list-price estimate for the execution, in microdollars.
  # It is a reference, not the subscription bill; the ledger keeps its own
  # estimate from the transcript.
  def change do
    alter table(:runner_executions) do
      add :cost_micros, :bigint
    end
  end
end
