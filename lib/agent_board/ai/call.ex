defmodule AgentBoard.AI.Call do
  @moduledoc "One row per model call: what was asked, what it cost, how long, and whether it parsed."

  use Ecto.Schema

  @type t :: %__MODULE__{}
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :engine,
             :model,
             :tier,
             :status,
             :input_tokens,
             :output_tokens,
             :cost_micros,
             :duration_ms,
             :parse_state,
             :error,
             :inserted_at
           ]}

  schema "ai_calls" do
    field :name, :string
    field :engine, :string
    field :model, :string
    field :tier, :string
    field :status, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :cost_micros, :integer, default: 0
    field :duration_ms, :integer, default: 0
    field :parse_state, :string
    field :json, :map
    field :input_hash, :string
    field :error, :string
    field :task_id, :integer
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(call, attrs) do
    call
    |> cast(attrs, [
      :name,
      :engine,
      :model,
      :tier,
      :status,
      :input_tokens,
      :output_tokens,
      :cost_micros,
      :duration_ms,
      :parse_state,
      :json,
      :input_hash,
      :error,
      :task_id
    ])
    |> validate_required([:name, :engine, :status])
  end
end
