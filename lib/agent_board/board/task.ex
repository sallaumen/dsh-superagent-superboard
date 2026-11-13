defmodule AgentBoard.Board.Task do
  @moduledoc "An issue, a manual card, or a ticket the agent is working on."
  use Ecto.Schema

  @type t :: %__MODULE__{}
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [:id, :kind, :number, :title, :state, :url, :author, :stopped, :archived]}

  @states ~w(draft queued running retrying question ready blocked done closed stopped archived)

  # The split's classification (the `:propose_tasks` call): where the work
  # lands and how big it is. The registry's schema reads these lists, so
  # the model and the column cannot disagree.
  @work_types ~w(ui backend docs bug research infra)
  @sizes ~w(S M L)

  @doc "The kinds of work a split task can be."
  def work_types, do: @work_types

  @doc "The sizes a split task can be: S, M, L."
  def sizes, do: @sizes

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
    field :github_reopened_at, :utc_datetime
    field :state_changed_at, :utc_datetime
    field :request_key, :string
    field :work_type, :string
    field :size, :string
    field :executor, :string
    field :blocker_for_task_id, :integer
    field :held, :boolean, default: false
    field :released_at, :utc_datetime

    belongs_to :repository, AgentBoard.Board.Repository
    belongs_to :origin_task, AgentBoard.Board.Task
    belongs_to :objective, AgentBoard.Board.Objective
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
      :request_key,
      :work_type,
      :size,
      :executor,
      :blocker_for_task_id,
      :objective_id,
      :held,
      :released_at
    ])
    |> validate_required([:title, :repository_id])
    |> validate_inclusion(:state, @states)
    |> validate_inclusion(:work_type, @work_types)
    |> validate_inclusion(:size, @sizes)
    |> validate_inclusion(:executor, AgentBoard.Executors.all())
    |> foreign_key_constraint(:blocker_for_task_id)
    |> unique_constraint([:repository_id, :kind, :number])
    |> unique_constraint([:repository_id, :request_key])
  end
end
