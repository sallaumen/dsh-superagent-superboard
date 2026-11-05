defmodule AgentBoard.Repo.Migrations.UpdateObanToV14 do
  @moduledoc "Oban 2.24 requires the v14 schema."
  use Ecto.Migration

  def up, do: Oban.Migrations.up(version: 14)
  def down, do: Oban.Migrations.down(version: 13)
end
