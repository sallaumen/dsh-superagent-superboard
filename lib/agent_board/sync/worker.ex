defmodule AgentBoard.Sync.Worker do
  @moduledoc """
  The durable sync job. Oban retries it, the supervisor restarts it, and the
  dashboard shows it — no hand-rolled loop.

  Schedule it with `AgentBoard.Sync.Scheduler` (or an Oban cron plugin).
  """
  use Oban.Worker, queue: :sync, max_attempts: 3, unique: [period: 30]

  @impl Oban.Worker
  def perform(_job) do
    AgentBoard.Sync.all()
    :ok
  rescue
    # A spent quota is not a broken job: snooze for as long as GitHub asked
    # instead of burning the retry budget on requests that cannot succeed.
    error in AgentBoard.GitHub.RateLimited ->
      {:snooze, max(error.retry_after, 60)}
  end
end
