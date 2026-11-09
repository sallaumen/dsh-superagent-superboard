defmodule AgentBoard.Board.Activity do
  @moduledoc """
  The board's append-only activity: what happened in a repository, the last
  sync outcome and the snapshot the freshness header reads.

  It is the event-log side of the Board context, kept apart from the task,
  comment and pull-request reads so that a new event kind or a change to the
  freshness window has one place to land. `AgentBoard.Board` delegates the
  public functions here; the table and the schema stay in the context.
  """

  import Ecto.Query, warn: false

  alias AgentBoard.Board.Event
  alias AgentBoard.Repo

  @doc "The recent activity for a repository."
  def events(repository, limit \\ 20)

  def events(nil, _limit), do: []

  def events(repository, limit) do
    Repo.all(
      from e in Event,
        where: e.repository_id == ^repository.id,
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: ^limit
    )
  end

  @doc "The latest sync outcome, independent of the activity window."
  def latest_sync(repository) do
    Repo.one(
      from e in Event,
        where: e.repository_id == ^repository.id and e.kind in ["sync", "sync_error"],
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: 1
    )
  end

  @doc "The newest attempt and the newest success, for the freshness snapshot."
  def sync_snapshot(repository) do
    events =
      Repo.all(
        from e in Event,
          where: e.repository_id == ^repository.id and e.kind in ["sync", "sync_error"],
          order_by: [desc: e.inserted_at, desc: e.id],
          limit: 50
      )

    %{
      last_attempt: List.first(events),
      last_success: Enum.find(events, &(&1.kind == "sync"))
    }
  end

  @doc "Record an activity row."
  def log_event(repository_id, kind, subject, payload \\ %{}) do
    %Event{}
    |> Event.changeset(%{
      repository_id: repository_id,
      kind: kind,
      subject: subject,
      payload: payload
    })
    |> Repo.insert()
  end
end
