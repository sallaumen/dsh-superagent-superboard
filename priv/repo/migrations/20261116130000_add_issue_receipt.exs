defmodule AgentBoard.Repo.Migrations.AddIssueReceipt do
  use Ecto.Migration

  def change do
    alter table(:tasks), do: add(:issue_receipt, :map)
  end
end
