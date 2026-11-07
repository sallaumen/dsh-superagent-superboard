defmodule AgentBoard.Board.Commit do
  @moduledoc "A commit the sync saw on the repository's default branch."
  use Ecto.Schema
  import Ecto.Changeset

  schema "commits" do
    field :sha, :string
    field :author, :string
    field :message, :string
    field :authored_at, :utc_datetime
    field :committed_at, :utc_datetime

    belongs_to :repository, AgentBoard.Board.Repository

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(commit, attrs) do
    commit
    |> cast(attrs, [:sha, :author, :message, :authored_at, :committed_at, :repository_id])
    |> validate_required([:sha, :repository_id])
    |> unique_constraint([:repository_id, :sha])
  end
end
