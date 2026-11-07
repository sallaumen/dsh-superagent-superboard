defmodule AgentBoard.AutoRetry.Attempt do
  @moduledoc """
  One automatic retry the board asked the runner for, keyed by the
  Assignment that failed (unique).

  `outcome` moves `sending` -> `retried` | `refused` | `unknown_ticket` |
  `error`, or to `unreachable` / `timeout` when the request did not get an
  answer; only those two may be claimed again, and only while the same
  Assignment is still the ticket's latest failure.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @outcomes ~w(sending retried refused unknown_ticket unreachable timeout error)

  schema "agent_retries" do
    field :ticket_id, :string
    field :assignment_id, :string
    field :attempt, :integer
    field :cause, :string
    field :stage, :string
    field :summary, :string
    field :failed_at, :utc_datetime
    field :outcome, :string
    field :detail, :string

    timestamps(type: :utc_datetime)
  end

  @doc "The outcomes that leave the Assignment open to another claim."
  def unanswered, do: ~w(unreachable timeout)

  @doc false
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :ticket_id,
      :assignment_id,
      :attempt,
      :cause,
      :stage,
      :summary,
      :failed_at,
      :outcome,
      :detail
    ])
    |> validate_required([:ticket_id, :assignment_id, :attempt, :outcome])
    |> validate_inclusion(:outcome, @outcomes)
    |> unique_constraint(:assignment_id)
  end
end
