defmodule AgentBoard.Routing.Decision do
  @moduledoc """
  The router's suggestion for a task the board created and the owner's
  choice, one row per task: suggested (nil when no executor could take it),
  chosen, the mode, the reasons in the owner's words, the alternatives,
  the snapshot of the signals read and who decided (the composer, the
  voice or the API).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @deciders ~w(composer voice api)

  schema "routing_decisions" do
    field :suggested, :string
    field :chosen, :string
    field :mode, :string
    field :reasons, {:array, :string}, default: []
    field :alternatives, {:array, :string}, default: []
    field :signals, :map, default: %{}
    field :decided_by, :string

    belongs_to :task, AgentBoard.Board.Task

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Who can decide: the composer, the voice or the API."
  def deciders, do: @deciders

  @doc false
  def changeset(decision, attrs) do
    executors = AgentBoard.Executors.all()

    decision
    |> cast(attrs, [
      :task_id,
      :suggested,
      :chosen,
      :mode,
      :reasons,
      :alternatives,
      :signals,
      :decided_by
    ])
    |> validate_required([:task_id, :chosen, :mode, :decided_by])
    |> validate_inclusion(:suggested, executors)
    |> validate_inclusion(:chosen, executors)
    |> validate_inclusion(:mode, ~w(suggest))
    |> validate_inclusion(:decided_by, @deciders)
    |> unique_constraint(:task_id)
  end
end
