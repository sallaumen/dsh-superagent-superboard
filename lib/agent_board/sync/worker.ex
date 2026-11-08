defmodule AgentBoard.Sync.Worker do
  @moduledoc """
  The durable sync job. Oban retries it, the supervisor restarts it, and the
  dashboard shows it — no hand-rolled loop.

  `Oban.Plugins.Cron` enqueues it every five minutes (`config/config.exs`);
  the owner's "sync now" enqueues one more. A job scheduled more than one
  cron period ago is cancelled as superseded: the cron has enqueued a newer
  one since. That is what `Oban.Lifeline` hands back after a restart killed
  a run, and syncing it again would only spend GitHub quota.
  """
  use Oban.Worker, queue: :sync, max_attempts: 3, unique: [period: 30]

  # The crontab's period. A retry or a snooze that woke is scheduled seconds
  # before it runs; an orphan Lifeline rescued, at least `rescue_after` ago.
  @superseded_after_seconds 5 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    if superseded?(job) do
      {:cancel, "superseded: scheduled at #{job.scheduled_at}, before the last cron run"}
    else
      sync()
    end
  end

  defp sync do
    AgentBoard.Sync.all()
    :ok
  rescue
    # A spent quota is not a broken job: snooze for as long as GitHub asked
    # instead of burning the retry budget on requests that cannot succeed.
    error in AgentBoard.GitHub.RateLimited ->
      {:snooze, max(error.retry_after, 60)}
  end

  defp superseded?(%Oban.Job{scheduled_at: %DateTime{} = at}),
    do: DateTime.diff(DateTime.utc_now(), at) > @superseded_after_seconds

  defp superseded?(%Oban.Job{}), do: false
end
