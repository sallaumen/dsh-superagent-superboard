defmodule AgentBoard.Board.Objective do
  @moduledoc "A group of tasks with one done criterion."
  use Ecto.Schema
  import Ecto.Changeset

  schema "objectives" do
    field :title, :string
    field :done_criterion, :string
    field :request_key, :string
    field :request_text, :string
    field :spec, :map
    field :issue_number, :integer
    field :issue_url, :string

    belongs_to :repository, AgentBoard.Board.Repository
    has_many :tasks, AgentBoard.Board.Task

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(objective, attrs) do
    objective
    |> cast(attrs, [
      :repository_id,
      :title,
      :done_criterion,
      :request_key,
      :request_text,
      :spec,
      :issue_number,
      :issue_url
    ])
    |> validate_required([:repository_id, :title, :done_criterion])
    |> unique_constraint([:repository_id, :request_key])
  end
end
