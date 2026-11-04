defmodule AgentBoard.Board.PullRequest do
  @moduledoc "A pull request, with the review and CI rollups the board shows."
  use Ecto.Schema
  import Ecto.Changeset

  schema "pull_requests" do
    field :number, :integer
    field :title, :string
    field :state, :string
    field :url, :string
    field :author, :string
    field :opened_at, :utc_datetime
    field :merged_at, :utc_datetime
    field :review_state, :string
    field :checks_state, :string
    field :checks_failed, :string

    belongs_to :repository, AgentBoard.Board.Repository
    has_many :reviews, AgentBoard.Board.Review

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pull_request, attrs) do
    pull_request
    |> cast(attrs, [
      :number,
      :title,
      :state,
      :url,
      :author,
      :opened_at,
      :merged_at,
      :review_state,
      :checks_state,
      :checks_failed,
      :repository_id
    ])
    |> validate_required([:number, :title, :state, :repository_id])
    |> validate_inclusion(:state, ~w(open merged closed))
    |> unique_constraint([:repository_id, :number])
  end
end
