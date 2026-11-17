defmodule AgentBoard.Board.TaskPullLinks.Evidence do
  @moduledoc "Match a task to pull request evidence from its own repository."
  alias AgentBoard.Board.Repository
  alias AgentBoard.GitHub

  @doc "Newest comment with a local PR URL wins; otherwise try the task body. Comments arrive oldest first."
  @spec named_number(String.t() | nil, [map()], Repository.t() | nil) :: integer() | nil
  def named_number(body, comments, repository) do
    Enum.find_value(Enum.reverse(comments), &pull_number(&1.body, repository)) ||
      pull_number(body, repository)
  end

  @doc "Index each task's explicit link once, retaining the repository as part of the PR identity."
  @spec named_refs([map()], map(), map()) :: %{optional(integer()) => {integer(), integer()}}
  def named_refs(tasks, comments, repositories) do
    for task <- tasks,
        repo = repositories[task.repository_id],
        number = named_number(task.body, Map.get(comments, task.id, []), repo),
        into: %{},
        do: {task.id, {task.repository_id, number}}
  end

  @doc "Candidate ticket PRs, highest number first, only for tasks still without a saved named PR."
  @spec thread_refs([map()], map(), map()) :: %{optional(integer()) => [{integer(), integer()}]}
  def thread_refs(tasks, tickets, named) do
    for task <- tasks,
        not Map.has_key?(named, task.id),
        numbers = get_in(tickets, [task.number, "own_threads"]),
        is_list(numbers) and numbers != [],
        into: %{} do
      refs = numbers |> Enum.sort(:desc) |> Enum.map(&{task.repository_id, &1})
      {task.id, refs}
    end
  end

  @doc "Keep the first observed pull in each task's ordered thread candidates."
  @spec thread_matches(map(), map()) :: map()
  def thread_matches(candidates, pulls) do
    for {id, refs} <- candidates,
        pull = Enum.find_value(refs, &Map.get(pulls, &1)),
        into: %{},
        do: {id, pull}
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
end
