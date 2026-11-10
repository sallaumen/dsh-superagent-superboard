defmodule AgentBoard.MessagePoller do
  @moduledoc """
  Reads recent GitHub issue comments once per repository and pushes changes to
  open boards. The normal five-minute sync remains the durable fallback.
  """
  use GenServer
  import Ecto.Query, warn: false
  require Logger

  alias AgentBoard.{Board, GitHub, Repo}
  alias AgentBoard.Board.{Comment, Event, Repository, Task}

  @interval 30_000
  @bootstrap_window 10 * 60
  @max_pages 10
  @max_failure_wait 30 * 60

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{started_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(:poll, state) do
    schedule()
    {:noreply, if(token_available?(), do: poll(state), else: state)}
  end

  defp schedule do
    Process.send_after(
      self(),
      :poll,
      Application.get_env(:agent_board, :message_poll_interval, @interval)
    )
  end

  defp token_available? do
    token = Application.get_env(:agent_board, :github_token, System.get_env("GITHUB_TOKEN", ""))
    is_binary(token) and token != ""
  end

  @doc "One bounded read per active repository; errors keep the last good cursor."
  def poll(state \\ %{}, client \\ GitHub.client()) do
    now = DateTime.utc_now()

    Repo.all(from r in Repository, where: r.active)
    |> Enum.reduce(state, fn repository, acc ->
      previous = Map.get(acc, repository.id, %{})

      if retry_later?(previous, now) do
        acc
      else
        since = previous[:since] || bootstrap_since(repository, state[:started_at] || now, now)

        try do
          {comments, cursor} = pages(client, repository, DateTime.add(since, -2, :second))
          if store(repository, comments), do: Board.broadcast(repository.id)
          Map.put(acc, repository.id, %{since: cursor || now})
        rescue
          error in GitHub.RateLimited ->
            seconds = retry_seconds(error.retry_after)
            Map.put(acc, repository.id, Map.put(previous, :retry_at, DateTime.add(now, seconds)))

          error ->
            Logger.warning(
              "message poll unavailable for #{repository.owner}/#{repository.name}: #{inspect(error.__struct__)}"
            )

            # 60 s, doubling to half an hour: a broken repository is not read
            # every 30 s for as long as it stays broken.
            failures = Map.get(previous, :failures, 0) + 1
            wait = min(60 * Integer.pow(2, failures - 1), @max_failure_wait)
            retry = %{failures: failures, retry_at: DateTime.add(now, wait)}
            Map.put(acc, repository.id, Map.merge(previous, retry))
        end
      end
    end)
  end

  # The cursor lives in memory, so a restart reads back to the last successful
  # sync before this boot (the poller was reading until then); a sync that
  # finished after the boot read only a few tasks and would hide the outage.
  # Never less than the ten-minute window; a long outage is read in
  # @max_pages steps, as any backlog.
  defp bootstrap_since(repository, started_at, now) do
    window = DateTime.add(now, -@bootstrap_window, :second)

    Repo.one(
      from e in Event,
        where:
          e.repository_id == ^repository.id and e.kind == "sync" and
            e.inserted_at < ^started_at,
        select: max(e.inserted_at)
    )
    |> case do
      nil -> window
      synced_at -> Enum.min([synced_at, window], DateTime)
    end
  end

  defp retry_later?(%{retry_at: at}, now), do: DateTime.compare(at, now) == :gt
  defp retry_later?(_previous, _now), do: false

  defp retry_seconds(value) do
    case Integer.parse(to_string(value)) do
      {seconds, ""} when seconds > 0 -> seconds
      _ -> 60
    end
  end

  # The comments since `since`, oldest update first, and the cursor for the
  # next poll: nil when everything was read, the last comment's update when
  # the page limit stopped the read.
  defp pages(client, repository, since, page \\ 1, found \\ [])

  defp pages(_client, _repository, _since, page, found) when page > @max_pages do
    comments = found |> Enum.reverse() |> List.flatten()
    {comments, comments |> List.last() |> updated_at()}
  end

  defp pages(client, repository, since, page, found) do
    {comments, more?} =
      GitHub.repository_issue_comments(
        client,
        repository.owner,
        repository.name,
        since,
        page
      )

    if more?,
      do: pages(client, repository, since, page + 1, [comments | found]),
      else: {found |> Enum.reverse() |> Kernel.++([comments]) |> List.flatten(), nil}
  end

  defp updated_at(%{"updated_at" => at}) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, at, _offset} -> at
      _ -> nil
    end
  end

  defp updated_at(_comment), do: nil

  defp store(_repository, []), do: false

  defp store(repository, comments) do
    numbered =
      comments
      |> Enum.map(&{issue_number(&1["issue_url"]), &1})
      |> Enum.filter(fn {number, _} -> is_integer(number) end)

    numbers = Enum.map(numbered, &elem(&1, 0))

    tasks =
      Repo.all(
        from t in Task,
          where: t.repository_id == ^repository.id and t.number in ^numbers
      )
      |> Map.new(&{&1.number, &1})

    candidates =
      for {number, comment} <- numbered,
          task = tasks[number],
          is_integer(comment["id"]),
          do: {task, comment}

    task_ids = Enum.map(candidates, fn {task, _} -> task.id end)
    github_ids = Enum.map(candidates, fn {_, comment} -> comment["id"] end)

    existing =
      Repo.all(
        from c in Comment,
          where: c.task_id in ^task_ids and c.github_id in ^github_ids,
          select: {c.task_id, c.github_id, c.author, c.body}
      )
      |> Map.new(fn {task_id, id, author, body} -> {{task_id, id}, {author, body}} end)

    agent_login = Application.get_env(:agent_board, :agent_login, "sallaumen-agent")

    Enum.reduce(candidates, false, fn {task, comment}, changed? ->
      author = get_in(comment, ["user", "login"]) || "unknown"
      key = {task.id, comment["id"]}

      if Map.get(existing, key) == {author, comment["body"] || ""} do
        changed?
      else
        {:ok, _} = Board.upsert_comment(task, comment, agent_login)
        true
      end
    end)
  end

  defp issue_number(url) when is_binary(url) do
    case Regex.run(~r{/issues/(\d+)$}, url) do
      [_, number] -> String.to_integer(number)
      _ -> nil
    end
  end

  defp issue_number(_), do: nil
end
