defmodule AgentBoard.Board.Objective do
  @moduledoc "A group of tasks with one done criterion."
  use Ecto.Schema

  @type t :: %__MODULE__{}
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

  @doc "Returns distinct task IDs in first-seen order when at least two tasks form a group."
  @spec group_task_ids([integer()]) :: {:ok, [integer()]} | {:error, :not_a_group}
  def group_task_ids(task_ids) do
    case Enum.uniq(task_ids) do
      [_, _ | _] = ids -> {:ok, ids}
      _ -> {:error, :not_a_group}
    end
  end

  @doc "Counts merged tasks. An objective is done only when it has tasks and all are done."
  @spec progress([AgentBoard.Board.Task.t()]) :: %{
          total: non_neg_integer(),
          merged: non_neg_integer(),
          done?: boolean()
        }
  def progress(tasks) do
    total = length(tasks)
    merged = Enum.count(tasks, &(&1.state == "done"))

    %{total: total, merged: merged, done?: total > 0 and merged == total}
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
