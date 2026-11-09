defmodule AgentBoard.AgentAccess.Dismissal do
  @moduledoc "The owner set aside a person's request; a later mention brings it back."
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_access_dismissals" do
    field :login, :string
    field :dismissed_at, :utc_datetime

    belongs_to :superagent, AgentBoard.Superagents.Superagent

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(dismissal, attrs) do
    dismissal
    |> cast(attrs, [:superagent_id, :login, :dismissed_at])
    |> validate_required([:superagent_id, :login, :dismissed_at])
    |> unique_constraint([:superagent_id, :login])
  end
end
