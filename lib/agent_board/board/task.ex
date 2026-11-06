defmodule AgentBoard.Board.Task do
  @moduledoc "An issue, a manual card, or a ticket the agent is working on."
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [:id, :kind, :number, :title, :state, :url, :author, :stopped, :archived]}

  @states ~w(queued running question ready blocked done closed stopped archived)

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
    field :started_at, :utc_datetime
    field :state_changed_at, :utc_datetime
    field :request_key, :string

    belongs_to :repository, AgentBoard.Board.Repository
    belongs_to :origin_task, AgentBoard.Board.Task
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
      :repository_id,
      :started_at,
      :state_changed_at,
      :origin_task_id,
      :request_key
    ])
    |> validate_required([:title, :repository_id])
    |> validate_inclusion(:state, @states)
    |> unique_constraint([:repository_id, :kind, :number])
    |> unique_constraint([:repository_id, :request_key])
  end
end
