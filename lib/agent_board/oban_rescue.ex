defmodule AgentBoard.ObanRescue do
  @moduledoc """
  On boot, every job left `executing` belongs to the process that just died.

  The board is a single node: at application start there is no live job to
  protect. Oban's Lifeline judges by time alone and waits 30 minutes, so a
  restart mid-sync left a zombie row holding the queue for half an hour.
  Rescuing the orphans immediately puts the sync and usage queues back to
  work instead.
  """

  import Ecto.Query, warn: false

  require Logger

  alias AgentBoard.Repo

  @doc """
  Returns every `executing` job to work, now: retryable while it has attempts
  left, discarded otherwise, as `Oban.Lifeline` does. The attempt is not
  counted again: the dead run counted when it started, and a job already at
  its limit would break the table's `attempt_range` check and fail the whole
  sweep. Returns the count.
  """
  @spec rescue_orphans() :: {integer(), nil} | {:error, term()}
  def rescue_orphans do
    now = DateTime.utc_now()
    error = %{"at" => DateTime.to_iso8601(now), "error" => "rescued after a board restart"}
    orphans = from(j in Oban.Job, where: j.state == "executing")

    {retried, nil} =
      Repo.update_all(
        where(orphans, [j], j.attempt < j.max_attempts),
        set: [state: "retryable", scheduled_at: now, attempted_at: now, errors: [error]]
      )

    {discarded, nil} =
      Repo.update_all(orphans, set: [state: "discarded", discarded_at: now, errors: [error]])

    {retried + discarded, nil}
  rescue
    exception ->
      Logger.error("could not rescue orphaned Oban jobs: #{Exception.message(exception)}")
      {:error, exception}
  end
end
