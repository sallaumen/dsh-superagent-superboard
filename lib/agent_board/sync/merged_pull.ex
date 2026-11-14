defmodule AgentBoard.Sync.MergedPull do
  @moduledoc """
  Mirror a newly ended ticket's exact merged pull ahead of the regular sync.
  Both writers run on the serial sync queue. Older tickets, missed signals
  and jobs delayed beyond a cron period are covered by the regular mirror.
  """
  use Oban.Worker,
    queue: :sync,
    max_attempts: 2,
    unique: [period: 300, states: [:available, :scheduled, :executing, :retryable, :completed]]

  import Ecto.Query
  alias AgentBoard.{Actions, GitHub, Repo, Sync}
  alias AgentBoard.Board.{PullRequest, Repository}

  def enqueue_recent(repo, tickets, now \\ DateTime.utc_now())

  def enqueue_recent(%Repository{active: true} = repo, tickets, now) do
    if GitHub.configured?(), do: enqueue(repo, tickets, now)
  end

  def enqueue_recent(_, _, _), do: :ok

  defp enqueue(repo, tickets, now) do
    slug = String.downcase("#{repo.owner}/#{repo.name}")

    numbers =
      for %{"repository" => name, "ended_at" => %DateTime{} = at, "merged_threads" => numbers} <-
            tickets,
          is_binary(name) and String.downcase(name) == slug,
          DateTime.diff(now, at) in 0..299,
          number <- numbers,
          uniq: true,
          do: number

    Enum.each(numbers, fn n ->
      unless mirrored?(repo.id, n) do
        Actions.run(
          :sync_merged_pull,
          %{repository: repo, number: n},
          Actions.system("ticket_poller")
        )
      end
    end)
  end

  @impl true
  def perform(%Oban.Job{args: %{"repo_id" => id, "number" => number}, inserted_at: at}) do
    with true <- is_nil(at) or DateTime.diff(DateTime.utc_now(), at) < 300,
         true <- GitHub.configured?(),
         %Repository{active: true} = repo <- Repo.get(Repository, id),
         false <- mirrored?(id, number) do
      Sync.sync_merged_pull(GitHub.client(), repo, number)
    else
      _ -> :ok
    end
  rescue
    e in GitHub.RateLimited ->
      {:snooze, max(60, e.retry_after || 60)}

    e in GitHub.HTTPError ->
      if e.status in [404, 410], do: :ok, else: {:error, Exception.message(e)}
  end

  defp mirrored?(id, n) do
    Repo.exists?(
      from p in PullRequest,
        where: p.repository_id == ^id and p.number == ^n and not is_nil(p.merged_at)
    )
  end
end
