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

  alias AgentBoard.{GitHub, Sync}

  # The crontab's period. A retry or a snooze that woke is scheduled seconds
  # before it runs; an orphan Lifeline rescued, at least `rescue_after` ago.
  @superseded_after_seconds 5 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    cond do
      superseded?(job) ->
        {:cancel, "superseded: scheduled at #{job.scheduled_at}, before the last cron run"}

      # A server with no token (a worktree on the shared database) can only
      # fail, and each failure tells the live board GitHub is down.
      Sync.repositories?() and not GitHub.configured?() ->
        {:cancel, "no GITHUB_TOKEN: this server does not sync"}

      true ->
        Sync.run() |> outcome()
    end
  end

  # A spent quota is not a broken job: snooze for as long as GitHub asked
  # instead of burning the retry budget on requests that cannot succeed.
  # When every repository failed, Oban retries with a backoff. When only some
  # did, a retry would read the healthy ones again: their failures are
  # already events, and the next cron run reads them again.
  defp outcome(results) do
    failures = Enum.filter(results, &match?({:error, _exception}, &1))

    case Enum.find(failures, &match?({:error, %GitHub.RateLimited{}}, &1)) do
      {:error, %GitHub.RateLimited{retry_after: seconds}} ->
        {:snooze, seconds |> max(60) |> min(3_600)}

      nil when failures != [] and length(failures) == length(results) ->
        {:error, failures |> List.first() |> elem(1) |> Exception.message()}

      nil ->
        :ok
    end
  end

  defp superseded?(%Oban.Job{scheduled_at: %DateTime{} = at}),
    do: DateTime.diff(DateTime.utc_now(), at) > @superseded_after_seconds

  defp superseded?(%Oban.Job{}), do: false
end
