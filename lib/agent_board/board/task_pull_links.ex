defmodule AgentBoard.Board.TaskPullLinks do
  @moduledoc "Reads the pull requests linked to tasks, scoped to their own repositories."

  import Ecto.Query

  alias AgentBoard.Board.{Comment, PullRequest, Repository, Task}
  alias AgentBoard.Board.TaskPullLinks.Evidence
  alias AgentBoard.Repo

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
    tasks
    |> named_pulls()
    |> Enum.filter(fn {_id, pull} -> pull.state in ["merged", "closed"] end)
    |> MapSet.new(&elem(&1, 0))
  end

  defp named_pulls(tasks) do
    {comments, repositories} = link_sources(tasks)
    refs = Evidence.named_refs(tasks, comments, repositories)
    pulls = refs |> Map.values() |> pulls_by_ref()

    for {id, ref} <- refs, pull = pulls[ref], into: %{}, do: {id, pull}
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

  defp pulls_by_ref([]), do: %{}

  defp pulls_by_ref(refs) do
    # An independent IN for each column would also load other repositories' PRs
    # with the same numbers. Keep each number attached to its own repository.
    scope =
      refs
      |> Enum.uniq()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.reduce(dynamic(false), fn {repo, numbers}, scope ->
        dynamic([p], ^scope or (p.repository_id == ^repo and p.number in ^numbers))
      end)

    Repo.all(from p in PullRequest, where: ^scope)
    |> Map.new(&{{&1.repository_id, &1.number}, &1})
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
    named = named_pulls(tasks)

    threads = Evidence.thread_refs(tasks, tickets, named)
    thread_pulls = threads |> Enum.flat_map(fn {_id, refs} -> refs end) |> pulls_by_ref()
    Map.merge(named, Evidence.thread_matches(threads, thread_pulls))
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

    number = Evidence.named_number(task.body, comments, repository)

    if repository && number, do: find_pull_request(repository, number)
  end

  @doc "A saved pull request in one repository, regardless of its archive page."
  def find_pull_request(%Repository{id: repository_id}, number) when is_integer(number) do
    Repo.get_by(PullRequest, repository_id: repository_id, number: number)
  end
end
