defmodule AgentBoard.Conversation.Turn do
  @moduledoc """
  One turn of the owner's spoken conversation with the board's agent.

  `role` is `owner`, `agent` or `summary`. An agent turn may carry a
  `proposal` (a write the owner must confirm by voice) whose lifecycle is
  `proposal_status`: `proposed` → `confirmed` | `cancelled` | `expired`,
  and a confirmed question to a task's agent → `answered` once its reply
  was spoken. A task the voice created carries `%{"kind" => "created"}`
  with `done` → `undone` once "desfaz" closed it.
  A summary turn compresses every turn up to `summary_through_id`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}
  import Ecto.Changeset

  @roles ~w(owner agent summary)
  @statuses ~w(proposed confirmed cancelled expired answered done undone)

  schema "voice_turns" do
    field :role, :string
    field :text, :string
    field :repository_id, :id
    field :action, :string
    field :proposal, :map
    field :proposal_status, :string
    field :summary_through_id, :integer
    field :duration_ms, :integer
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(turn, attrs) do
    turn
    |> cast(attrs, [
      :role,
      :text,
      :repository_id,
      :action,
      :proposal,
      :proposal_status,
      :summary_through_id,
      :duration_ms
    ])
    |> validate_required([:role, :text])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:proposal_status, @statuses)
    |> validate_length(:text, max: 8_000)
  end
end
