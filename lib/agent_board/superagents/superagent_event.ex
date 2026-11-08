defmodule AgentBoard.Superagents.SuperagentEvent do
  @moduledoc "Append-only audit of a superagent lifecycle."
  use Ecto.Schema
  import Ecto.Changeset

  schema "superagent_events" do
    field :action, :string
    field :from_state, :string
    field :to_state, :string
    field :actor, :string
    field :detail, :string

    belongs_to :superagent, AgentBoard.Superagents.Superagent

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:superagent_id, :action, :from_state, :to_state, :actor, :detail])
    |> validate_required([:superagent_id, :action, :actor])
  end
end
