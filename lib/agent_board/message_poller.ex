defmodule AgentBoard.MessagePoller do
  @moduledoc """
  Reads recent GitHub issue comments once per repository and pushes changes to
  open boards. The normal five-minute sync remains the durable fallback.
  """
  use GenServer
  import Ecto.Query, warn: false
  require Logger

  alias AgentBoard.{Board, GitHub, Repo}
  alias AgentBoard.Board.{Comment, Repository, Task}

  @interval 30_000
  @bootstrap_window 10 * 60
  @max_pages 10

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
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
        since = previous[:since] || DateTime.add(now, -@bootstrap_window, :second)

        try do
          comments = pages(client, repository, DateTime.add(since, -2, :second))
          if store(repository, comments), do: Board.broadcast(repository.id)
          Map.put(acc, repository.id, %{since: now})
        rescue
          error in GitHub.RateLimited ->
            seconds = retry_seconds(error.retry_after)
            Map.put(acc, repository.id, Map.put(previous, :retry_at, DateTime.add(now, seconds)))

          error ->
            Logger.warning(
              "message poll unavailable for #{repository.owner}/#{repository.name}: #{inspect(error.__struct__)}"
            )

            acc
        end
      end
    end)
  end

  defp retry_later?(%{retry_at: at}, now), do: DateTime.compare(at, now) == :gt
  defp retry_later?(_previous, _now), do: false

  defp retry_seconds(value) do
    case Integer.parse(to_string(value)) do
      {seconds, ""} when seconds > 0 -> seconds
      _ -> 60
    end
  end

  defp pages(client, repository, since, page \\ 1, found \\ []) do
    if page > @max_pages, do: raise("message poll pagination limit reached")

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
      else: found |> Enum.reverse() |> Kernel.++([comments]) |> List.flatten()
  end

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
