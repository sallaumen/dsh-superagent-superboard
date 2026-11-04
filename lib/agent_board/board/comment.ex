defmodule AgentBoard.Board.Comment do
  @moduledoc "A message in the conversation: a GitHub comment on the task's issue."
  use Ecto.Schema
  import Ecto.Changeset

  schema "comments" do
    field :github_id, :integer
    field :author, :string
    field :body, :string
    field :kind, :string, default: "user"

    belongs_to :task, AgentBoard.Board.Task

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:github_id, :author, :body, :kind, :task_id])
    |> validate_required([:body, :task_id])
    |> validate_inclusion(:kind, ~w(user agent))
    |> unique_constraint([:task_id, :github_id])
  end
end
