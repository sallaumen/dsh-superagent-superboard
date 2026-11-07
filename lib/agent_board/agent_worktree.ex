defmodule AgentBoard.AgentWorktree do
  @moduledoc """
  The observable step of a running assignment: the worktree's uncommitted
  changes or its last commit.

  This is evidence from the filesystem, not the executor's private log. When
  the directory is missing, not a git repository, or gives no signal, the
  answer is `nil` and the board omits the step instead of inventing one.
  """

  alias AgentBoard.AgentWorktree.Cache

  @max_subject 80
  @default_ttl_ms 10_000

  @type observation :: %{step: map() | nil, last_activity_at: DateTime.t() | nil}

  @doc """
  A step for the ticket, or nil.

  `%{kind: :edit, code: path}` for uncommitted work; `%{kind: :commit,
  code: sha, note: subject}` for the last commit.
  """
  @spec step(map() | nil) :: map() | nil
  def step(ticket), do: ticket |> observe() |> field(:step)

  @doc """
  When the worktree last changed, or nil: the newest uncommitted file or,
  with a clean tree, the last commit. Ignored files (`_build`, `deps`) are
  not evidence; a test run is not the agent's own progress.
  """
  @spec last_activity_at(map() | nil) :: DateTime.t() | nil
  def last_activity_at(ticket), do: ticket |> observe() |> field(:last_activity_at)

  @doc """
  The step and the last activity together, from one `git status` and at most
  one `git log`, or nil without a worktree.

  The observation is shared: it is kept per directory for
  `:worktree_ttl_ms` (10 s, the poll interval, by default; 0 reads every
  time), so the renders inside that window ask `git` once between them.
  """
  @spec observe(map() | nil) :: observation() | nil
  def observe(%{"execution" => %{"directory" => dir}}) when is_binary(dir) do
    dir = Path.expand(dir)
    Cache.fetch(dir, ttl_ms(), fn -> read(dir) end)
  end

  def observe(_ticket), do: nil

  defp field(nil, _key), do: nil
  defp field(observation, key), do: Map.fetch!(observation, key)

  defp ttl_ms, do: Application.get_env(:agent_board, :worktree_ttl_ms, @default_ttl_ms)

  defp read(dir) do
    if File.dir?(dir) do
      case changed_files(dir) do
        [file | _rest] ->
          %{
            step: %{kind: :edit, code: file, note: nil},
            # A deleted file is a change without a time; the commit answers then.
            last_activity_at: changed_at(dir, file) || commit_at(last_commit(dir))
          }

        [] ->
          commit = last_commit(dir)
          %{step: commit_step(commit), last_activity_at: commit_at(commit)}
      end
    end
  end

  defp changed_at(dir, file) do
    case mtime(dir, file) do
      0 -> nil
      posix -> DateTime.from_unix!(posix)
    end
  end

  defp changed_files(dir) do
    case git(dir, ["status", "--porcelain=v1", "--untracked-files=all"]) do
      {:ok, ""} ->
        []

      {:ok, output} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&String.slice(&1, 3..-1//1))
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.uniq()
        |> Enum.sort_by(&mtime(dir, &1), :desc)

      :error ->
        []
    end
  end

  # One `git log` answers both the step (sha and subject) and the activity
  # (the committer time).
  defp last_commit(dir) do
    with {:ok, output} <- git(dir, ["log", "-1", "--format=%h%x00%ct%x00%s"]),
         [sha, time, subject] when sha != "" <- String.split(output, "\0", parts: 3) do
      %{sha: sha, time: time, subject: subject}
    else
      _ -> nil
    end
  end

  defp commit_step(nil), do: nil
  defp commit_step(commit), do: %{kind: :commit, code: commit.sha, note: truncate(commit.subject)}

  defp commit_at(nil), do: nil

  defp commit_at(%{time: time}) do
    case Integer.parse(time) do
      {posix, ""} -> DateTime.from_unix!(posix)
      _ -> nil
    end
  end

  defp mtime(dir, file) do
    case File.stat(Path.join(dir, file), time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> mtime
      _ -> 0
    end
  end

  defp git(dir, args) do
    case System.cmd("git", ["-C", dir | args], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      _ -> :error
    end
  rescue
    _exception -> :error
  end

  defp truncate(subject) when byte_size(subject) <= @max_subject, do: subject
  defp truncate(subject), do: String.slice(subject, 0, @max_subject) <> "…"
end
