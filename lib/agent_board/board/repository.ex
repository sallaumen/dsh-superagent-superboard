defmodule AgentBoard.Board.Repository do
  @moduledoc "A repository the board tracks."
  use Ecto.Schema

  @type t :: %__MODULE__{}
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :owner, :name, :active]}

  schema "repositories" do
    field :owner, :string
    field :name, :string
    field :active, :boolean, default: true

    has_many :tasks, AgentBoard.Board.Task
    has_many :pull_requests, AgentBoard.Board.PullRequest

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(repository, attrs) do
    repository
    |> cast(attrs, [:owner, :name, :active])
    |> validate_required([:owner, :name])
    |> validate_length(:owner, max: 255)
    |> validate_length(:name, max: 255)
    |> validate_format(:owner, ~r/^[^\/\s]+$/, message: "must not contain a slash")
    |> validate_format(:name, ~r/^[^\/\s]+$/, message: "must not contain a slash")
    |> unique_constraint([:owner, :name])
  end
end
