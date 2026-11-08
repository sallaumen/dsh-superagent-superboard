defmodule AgentBoard.Board.Objective do
  @moduledoc "A group of tasks with one done criterion."
  use Ecto.Schema
  import Ecto.Changeset

  schema "objectives" do
    field :title, :string
    field :done_criterion, :string

    belongs_to :repository, AgentBoard.Board.Repository
    has_many :tasks, AgentBoard.Board.Task

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(objective, attrs) do
    objective
    |> cast(attrs, [:repository_id, :title, :done_criterion])
    |> validate_required([:repository_id, :title, :done_criterion])
  end
end
