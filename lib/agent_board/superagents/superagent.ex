defmodule AgentBoard.Superagents.Superagent do
  @moduledoc "One GitHub repository served by an external dsh-superagent."
  use Ecto.Schema
  import Ecto.Changeset

  @desired ~w(running paused stopped)
  @observed ~w(unknown starting ready paused error stopped)

  schema "superagents" do
    field :profile, :string
    field :port, :integer
    field :state_dir, :string
    field :desired_state, :string, default: "running"
    field :observed_state, :string, default: "unknown"
    field :observed_at, :utc_datetime
    field :last_error, :string
    field :max_workers, :integer, default: 3
    field :poll_seconds, :integer, default: 60
    field :created_by, :string, default: "owner"

    belongs_to :repository, AgentBoard.Board.Repository
    has_many :events, AgentBoard.Superagents.SuperagentEvent

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(superagent, attrs) do
    superagent
    |> cast(attrs, [
      :repository_id,
      :profile,
      :port,
      :state_dir,
      :desired_state,
      :observed_state,
      :observed_at,
      :last_error,
      :max_workers,
      :poll_seconds,
      :created_by
    ])
    |> validate_required([:repository_id, :profile, :port, :state_dir])
    |> validate_inclusion(:desired_state, @desired)
    |> validate_inclusion(:observed_state, @observed)
    |> validate_number(:port, greater_than: 0, less_than: 65_536)
    |> validate_number(:max_workers, greater_than: 0, less_than_or_equal_to: 32)
    |> validate_number(:poll_seconds, greater_than_or_equal_to: 60, less_than_or_equal_to: 3_600)
    |> unique_constraint(:repository_id)
    |> unique_constraint(:profile)
    |> unique_constraint(:port)
  end
end
