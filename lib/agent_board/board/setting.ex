defmodule AgentBoard.Board.Setting do
  @moduledoc "One board-wide setting: a key and its value."
  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  schema "settings" do
    field :value, :string
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
