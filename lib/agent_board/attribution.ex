defmodule AgentBoard.Attribution do
  @moduledoc """
  Which task an executor's session or a pull request worked for.

  The rules, from the strongest (docs/research/alfred.md, section 3.4):

  1. `:exact`: the session already names its task. The board dispatched it
     and kept the id, or the reader knows it (a DSH ticket's directory names
     its issue).
  2. `:pr_link`: the session linked a PR (a Claude Code `pr-link` line,
     repository and number) and that PR's body closes a task's issue.
  3. `:branch`: the session's branch is the head branch of a PR, in the same
     repository, whose body closes a task's issue.
  4. `{:repository, id}`: the session ran in a board repository with no PR
     that closes a task. Direct work, no task.
  5. `{:outside, name}`: a repository the board does not track, named by its
     directory.

  A PR without `Closes #n` has no task. The board never guesses by title,
  branch name or the conversation's content: a session is a map of metadata
  the reader chose field by field (`t:session/0`).

  Pure. `AgentBoard.Board.attribution_index/0` reads what `index/3` needs.
  """

  @typedoc """
  What a usage reader knows about one session. Every key is optional.

  - `:task_id`: the task the session was dispatched for (rule 1)
  - `:pr_links`: `%{repository: "owner/name", number: n}`, in the order the
    reader wants them tried
  - `:git_branch`: the branch the session worked on
  - `:origin_url`: the git remote (Codex keeps it per thread)
  - `:cwd`: the working directory
  """
  @type session :: %{
          optional(:task_id) => integer() | nil,
          optional(:pr_links) => [%{repository: String.t(), number: integer()}],
          optional(:git_branch) => String.t() | nil,
          optional(:origin_url) => String.t() | nil,
          optional(:cwd) => String.t() | nil
        }

  @type result ::
          {:task, integer(), :exact | :pr_link | :branch}
          | {:repository, integer()}
          | {:outside, String.t()}
          | :unknown

  @type repository :: %{id: integer(), owner: String.t(), name: String.t()}
  @type pull :: %{
          repository_id: integer(),
          number: integer(),
          head_ref: String.t() | nil,
          closes_issues: [integer()]
        }
  @type task :: %{id: integer(), repository_id: integer(), number: integer()}

  @opaque index :: %{
            repo_by_full_name: %{String.t() => integer()},
            repo_by_name: %{String.t() => [integer()]},
            pull: %{{integer(), integer()} => pull()},
            pulls_by_ref: %{{integer(), String.t()} => [pull()]},
            task: %{{integer(), integer()} => integer()}
          }

  # GitHub's closing keywords, each followed by its own reference:
  # "Closes #1, closes #2" closes both, "Closes #1, #2" only the first.
  @closing ~r/\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s+(?:([\w.-]+\/[\w.-]+)#(\d+)|#(\d+)|https:\/\/github\.com\/([\w.-]+\/[\w.-]+)\/issues\/(\d+))/i

  @doc """
  The issue numbers a PR body closes in its own repository, in the order the
  body names them, without repeats. A reference to another repository is
  not this repository's issue and is left out.
  """
  @spec closing_numbers(String.t() | nil, String.t(), String.t()) :: [integer()]
  def closing_numbers(nil, _owner, _name), do: []

  def closing_numbers(body, owner, name) when is_binary(body) do
    own = String.downcase("#{owner}/#{name}")

    @closing
    |> Regex.scan(body, capture: :all_but_first)
    |> Enum.flat_map(fn captures ->
      case Enum.map(captures, &blank_to_nil/1) ++ List.duplicate(nil, 5 - length(captures)) do
        [nil, nil, number, nil, nil] -> [number]
        [repo, number, nil, nil, nil] when repo != nil -> own_number(repo, number, own)
        [nil, nil, nil, repo, number] when repo != nil -> own_number(repo, number, own)
        _ -> []
      end
    end)
    |> Enum.map(&String.to_integer/1)
    |> Enum.uniq()
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp own_number(repo, number, own) do
    if String.downcase(repo) == own, do: [number], else: []
  end

  @doc "Indexes the board's repositories, pulls and issue tasks for `for_session/2`."
  @spec index([repository()], [pull()], [task()]) :: index()
  def index(repositories, pulls, tasks) do
    %{
      repo_by_full_name:
        Map.new(repositories, &{String.downcase("#{&1.owner}/#{&1.name}"), &1.id}),
      repo_by_name: Enum.group_by(repositories, &String.downcase(&1.name), & &1.id),
      pull: Map.new(pulls, &{{&1.repository_id, &1.number}, &1}),
      pulls_by_ref:
        pulls
        |> Enum.reject(&is_nil(&1.head_ref))
        |> Enum.group_by(&{&1.repository_id, &1.head_ref})
        |> Map.new(fn {key, list} -> {key, Enum.sort_by(list, & &1.number, :desc)} end),
      task: Map.new(tasks, &{{&1.repository_id, &1.number}, &1.id})
    }
  end

  @doc """
  The task a PR closes: the first issue its body names that is a task on the
  board, in the PR's repository. A PR that closes nothing has no task.
  """
  @spec task_for_pull(pull(), index()) :: integer() | nil
  def task_for_pull(pull, index) do
    Enum.find_value(pull.closes_issues || [], fn number ->
      Map.get(index.task, {pull.repository_id, number})
    end)
  end

  @doc "Where a session's work belongs, by the first rule that holds (see the moduledoc)."
  @spec for_session(session(), index()) :: result()
  def for_session(session, index) do
    repository_id = repository_of(session, index)

    cond do
      is_integer(session[:task_id]) ->
        {:task, session[:task_id], :exact}

      task_id = by_pr_link(session, index) ->
        {:task, task_id, :pr_link}

      task_id = by_branch(session[:git_branch], repository_id, index) ->
        {:task, task_id, :branch}

      repository_id ->
        {:repository, repository_id}

      name = directory_name(session[:cwd]) ->
        {:outside, name}

      true ->
        :unknown
    end
  end

  defp by_pr_link(session, index) do
    Enum.find_value(session[:pr_links] || [], fn link ->
      with repository_id when is_integer(repository_id) <-
             Map.get(index.repo_by_full_name, String.downcase(link.repository || "")),
           %{} = pull <- Map.get(index.pull, {repository_id, link.number}) do
        task_for_pull(pull, index)
      else
        _ -> nil
      end
    end)
  end

  # "HEAD" is a detached checkout, not a branch a PR can come from.
  defp by_branch(branch, repository_id, index)
       when is_binary(branch) and branch not in ["", "HEAD"] and is_integer(repository_id) do
    index.pulls_by_ref
    |> Map.get({repository_id, branch}, [])
    |> Enum.find_value(&task_for_pull(&1, index))
  end

  defp by_branch(_branch, _repository_id, _index), do: nil

  # The remote names the repository exactly; a PR link names it too; the
  # working directory only by the project folder's name, and only when one
  # board repository has that name.
  defp repository_of(session, index) do
    from_origin(session[:origin_url], index) ||
      Enum.find_value(session[:pr_links] || [], fn link ->
        Map.get(index.repo_by_full_name, String.downcase(link.repository || ""))
      end) ||
      from_cwd(session[:cwd], index)
  end

  defp from_origin(url, index) when is_binary(url) do
    case Regex.run(~r{github\.com[:/]([^/\s]+)/([^/\s]+?)(?:\.git)?/?$}, url) do
      [_, owner, name] -> Map.get(index.repo_by_full_name, String.downcase("#{owner}/#{name}"))
      _ -> nil
    end
  end

  defp from_origin(_url, _index), do: nil

  defp from_cwd(cwd, index) do
    with name when is_binary(name) <- directory_name(cwd),
         [repository_id] <- Map.get(index.repo_by_name, String.downcase(name)) do
      repository_id
    else
      _ -> nil
    end
  end

  @doc """
  The project folder a working directory belongs to: the folder that holds a
  `.claude/worktrees/<name>` worktree, or the directory itself.
  """
  @spec directory_name(String.t() | nil) :: String.t() | nil
  def directory_name(cwd) when is_binary(cwd) and cwd != "" do
    cwd
    |> String.split("/.claude/worktrees/")
    |> hd()
    |> Path.basename()
    |> case do
      "" -> nil
      name -> name
    end
  end

  def directory_name(_cwd), do: nil
end
