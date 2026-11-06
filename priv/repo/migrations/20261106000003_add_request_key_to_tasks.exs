defmodule AgentBoard.Repo.Migrations.AddRequestKeyToTasks do
  @moduledoc """
  A request the board itself created carries a key derived from what was
  asked, so a second submit of the same request (double click, reload, retry
  after a partial split) finds the task instead of opening a second issue.
  """
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :request_key, :string
    end

    create unique_index(:tasks, [:repository_id, :request_key], where: "request_key IS NOT NULL")
  end
end
