defmodule AgentBoard.Actions.Decision do
  @moduledoc """
  One decision about a board write (`AgentBoard.Actions`): which action, its
  risk, what was decided, by whom, through which door and when.

    * `decision` - `confirmed` (a person agreed), `automatic` (no
      confirmation was needed or a standing authorization covers it) or
      `refused` (nothing ran).
    * `evidence` - how a confirmation or an automatic run was justified:
      `phrase` (the person saw or heard the exact sentence and agreed),
      `words` (the person's own words ordered it, such as "cria direto") or
      `standing` (an authorization written in the maintainer contract).
    * `outcome` - `ok` or `error` once the effect ran; nil while it runs
      and for a refusal.
    * `detail` - why it was refused (`unconfirmed`, `phrase_changed`,
      `declined`) or what the error was.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @decisions ~w(confirmed automatic refused)
  @vias ~w(ui voice api system)

  schema "action_decisions" do
    field :action, :string
    field :risk, :string
    field :decision, :string
    field :by, :string
    field :via, :string
    field :evidence, :string
    field :phrase, :string
    field :words, :string
    field :subject, :string
    field :repository_id, :integer
    field :outcome, :string
    field :detail, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(decision, attrs) do
    decision
    |> cast(attrs, [
      :action,
      :risk,
      :decision,
      :by,
      :via,
      :evidence,
      :phrase,
      :words,
      :subject,
      :repository_id,
      :outcome,
      :detail
    ])
    |> validate_required([:action, :risk, :decision, :by, :via])
    |> validate_inclusion(:decision, @decisions)
    |> validate_inclusion(:risk, ~w(green yellow red))
    |> validate_inclusion(:via, @vias)
  end
end
