defmodule AgentBoard.Board.TaskPullLinks do
  @moduledoc "Reads the pull requests linked to tasks, scoped to their own repositories."

  import Ecto.Query

  alias AgentBoard.Board.{Comment, PullRequest, Repository, Task}
  alias AgentBoard.{GitHub, Repo}

  @doc """
  Task ids whose linked pull request is already merged or closed.

  A ready task can be stale after a human merges its PR: the issue/ticket
  report still says "ready for review". Merged work is done, so it does not
  belong in "Precisa de você" or in the "you" rail count. A task without a
  linked PR is not resolved by guessing.
  """
  @spec resolved_task_ids([Task.t()]) :: MapSet.t()
  def resolved_task_ids([]), do: MapSet.new()

  def resolved_task_ids(tasks) do
    {comments_by_task, repositories} = link_sources(tasks)

    # One read for every linked PR, not one per task: the overview filters
    # all ready tasks at once and the query count stays bounded.
    pulls = linked_pulls(tasks, comments_by_task, repositories)

    tasks
    |> Enum.filter(fn task ->
      number = linked_number(task, Map.get(comments_by_task, task.id, []), repositories)

      case Map.get(pulls, {task.repository_id, number}) do
        %PullRequest{state: state} when state in ["merged", "closed"] -> true
        _ -> false
      end
    end)
    |> MapSet.new(& &1.id)
  end

  # What a task's PR link is read from, in two reads for the whole list:
  # its comments (oldest first, so the last one with a link is the newest)
  # and its repository.
  defp link_sources(tasks) do
    ids = Enum.map(tasks, & &1.id)

    comments_by_task =
      Repo.all(
        from c in Comment, where: c.task_id in ^ids, order_by: [asc: c.inserted_at, asc: c.id]
      )
      |> Enum.group_by(& &1.task_id)

    repositories =
      Repo.all(
        from r in Repository, where: r.id in ^Enum.uniq(Enum.map(tasks, & &1.repository_id))
      )
      |> Map.new(&{&1.id, &1})

    {comments_by_task, repositories}
  end

  defp linked_pulls(tasks, comments_by_task, repositories) do
    candidates =
      tasks
      |> Enum.map(fn task ->
        {task.repository_id,
         linked_number(task, Map.get(comments_by_task, task.id, []), repositories)}
      end)
      |> Enum.filter(fn {_repository_id, number} -> is_integer(number) end)
      |> Enum.uniq()

    if candidates == [] do
      %{}
    else
      repository_ids = Enum.map(candidates, &elem(&1, 0)) |> Enum.uniq()
      numbers = Enum.map(candidates, &elem(&1, 1)) |> Enum.uniq()

      Repo.all(
        from p in PullRequest,
          where: p.repository_id in ^repository_ids and p.number in ^numbers
      )
      |> Map.new(&{{&1.repository_id, &1.number}, &1})
    end
  end

  defp linked_number(task, comments, repositories) do
    repository = Map.get(repositories, task.repository_id)

    Enum.find_value(Enum.reverse(comments), &pull_number(&1.body, repository)) ||
      pull_number(task.body, repository)
  end

  @doc """
  The pull request each task is linked to, by task id.

  The link is the PR URL the task's conversation or body names, or, failing
  that, the PR thread the task's ticket opened itself (`own_threads`). A task
  with neither is absent from the map: the board does not guess by title.
  """
  @spec linked_pull_requests([Task.t()], %{optional(integer()) => map()}) ::
          %{optional(integer()) => PullRequest.t()}
  def linked_pull_requests(tasks, tickets_by_number \\ %{})

  def linked_pull_requests([], _tickets), do: %{}

  def linked_pull_requests(tasks, tickets) do
    {comments_by_task, repositories} = link_sources(tasks)
    pulls = linked_pulls(tasks, comments_by_task, repositories)

    named =
      Enum.reduce(tasks, %{}, fn task, acc ->
        number = linked_number(task, Map.get(comments_by_task, task.id, []), repositories)

        case Map.get(pulls, {task.repository_id, number}) do
          nil -> acc
          pull -> Map.put(acc, task.id, pull)
        end
      end)

    # The rest fall back to the PR thread their ticket opened, read once for
    # all of them; the highest thread number wins, as before.
    unnamed = Enum.reject(tasks, &Map.has_key?(named, &1.id))
    threads = Map.new(unnamed, &{&1.id, own_threads(Map.get(tickets, &1.number))})
    thread_pulls = ticket_pulls(unnamed, threads)

    Enum.reduce(unnamed, named, fn task, acc ->
      pull =
        threads
        |> Map.fetch!(task.id)
        |> Enum.sort(:desc)
        |> Enum.find_value(&Map.get(thread_pulls, {task.repository_id, &1}))

      if pull, do: Map.put(acc, task.id, pull), else: acc
    end)
  end

  defp own_threads(nil), do: []
  defp own_threads(ticket), do: ticket["own_threads"] || []

  defp ticket_pulls(tasks, threads) do
    numbers = threads |> Map.values() |> List.flatten() |> Enum.uniq()

    if numbers == [] do
      %{}
    else
      repository_ids = Enum.uniq(Enum.map(tasks, & &1.repository_id))

      Repo.all(
        from p in PullRequest,
          where: p.repository_id in ^repository_ids and p.number in ^numbers
      )
      |> Map.new(&{{&1.repository_id, &1.number}, &1})
    end
  end

  @doc """
  The pull request a task names, from its body or the newest comment with a
  GitHub PR URL. The board never guesses by title.
  """
  def task_pull_request(%Task{} = task, comments) do
    repository =
      case task.repository do
        %Repository{} = repository -> repository
        _ -> Repo.get(Repository, task.repository_id)
      end

    number = linked_number(task, comments, %{task.repository_id => repository})

    if repository && number, do: find_pull_request(repository, number)
  end

  # Only a link to the task's own repository counts: the number alone would
  # match this repository's PR of the same number.
  defp pull_number(nil, _repository), do: nil
  defp pull_number(_text, nil), do: nil

  defp pull_number(text, %Repository{owner: owner, name: name}) do
    ~r{https://github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)}
    |> Regex.scan(text)
    |> Enum.find_value(fn [_, link_owner, link_name, number] ->
      if String.downcase("#{link_owner}/#{link_name}") == String.downcase("#{owner}/#{name}"),
        do: GitHub.number(number)
    end)
  end

  @doc "A saved pull request in one repository, regardless of its archive page."
  def find_pull_request(%Repository{id: repository_id}, number) when is_integer(number) do
    Repo.get_by(PullRequest, repository_id: repository_id, number: number)
  end
end
