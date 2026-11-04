defmodule AgentBoard.Board.Event do
  @moduledoc "An append-only activity record."
  use Ecto.Schema
  import Ecto.Changeset

  schema "events" do
    field :kind, :string
    field :subject, :string
    field :payload, :map

    belongs_to :repository, AgentBoard.Board.Repository

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:kind, :subject, :payload, :repository_id])
    |> validate_required([:kind])
  end
end
