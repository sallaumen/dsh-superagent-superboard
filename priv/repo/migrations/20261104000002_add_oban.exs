defmodule AgentBoard.Repo.Migrations.AddOban do
  @moduledoc "The durable job table Oban needs."
  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 12)
  def down, do: Oban.Migration.down(version: 1)
end
