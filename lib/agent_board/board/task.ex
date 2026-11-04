defmodule AgentBoard.Board.Task do
  @moduledoc "An issue, a manual card, or a ticket the agent is working on."
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [:id, :kind, :number, :title, :state, :url, :author, :stopped, :archived]}

  @states ~w(queued running ready blocked done closed stopped archived)

  schema "tasks" do
    field :kind, :string, default: "issue"
    field :number, :integer
    field :title, :string
    field :body, :string
    field :state, :string, default: "queued"
    field :url, :string
    field :author, :string
    field :stopped, :boolean, default: false
    field :archived, :boolean, default: false

    belongs_to :repository, AgentBoard.Board.Repository
    has_many :comments, AgentBoard.Board.Comment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :kind,
      :number,
      :title,
      :body,
      :state,
      :url,
      :author,
      :stopped,
      :archived,
      :repository_id
    ])
    |> validate_required([:title, :repository_id])
    |> validate_inclusion(:state, @states)
    |> unique_constraint([:repository_id, :kind, :number])
  end
end
