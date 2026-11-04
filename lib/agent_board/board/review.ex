defmodule AgentBoard.Board.Review do
  @moduledoc "One review of a pull request."
  use Ecto.Schema
  import Ecto.Changeset

  schema "reviews" do
    field :reviewer, :string
    field :state, :string
    field :submitted_at, :utc_datetime

    belongs_to :pull_request, AgentBoard.Board.PullRequest
  end

  @doc false
  def changeset(review, attrs) do
    review
    |> cast(attrs, [:reviewer, :state, :submitted_at, :pull_request_id])
    |> validate_required([:reviewer, :state])
    |> unique_constraint([:pull_request_id, :reviewer, :submitted_at])
  end
end
