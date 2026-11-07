defmodule AgentBoard.DailySummary.Entry do
  @moduledoc """
  One summary of the day, keyed by the owner's local date (unique).

  `content` holds the facts as the board observed them when the summary went
  out (string keys, see `AgentBoard.DailySummary.Facts`); the board renders
  and speaks that record and never recomputes it. `spoken_at` is claimed by
  the first board that speaks it; `dismissed_at` hides it on every board.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "daily_summaries" do
    field :local_date, :date
    field :generated_at, :utc_datetime
    field :window_start, :utc_datetime
    field :window_end, :utc_datetime
    field :content, :map
    field :spoken_at, :utc_datetime
    field :dismissed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:local_date, :generated_at, :window_start, :window_end, :content])
    |> validate_required([:local_date, :generated_at, :window_start, :window_end, :content])
    |> unique_constraint(:local_date)
  end
end
