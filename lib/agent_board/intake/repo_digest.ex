defmodule AgentBoard.Intake.RepoDigest do
  @moduledoc """
  What the split may know about a repository: its code paths and its own
  documents, read from GitHub and bounded.

  The refine and the split ran on the request's words alone, so they guessed
  at screens and files that one look at the tree would settle. This is help,
  never a gate: a repository the board cannot read splits as before.
  """

  alias AgentBoard.GitHub

  require Logger

  @documents ~w(AGENTS.md CLAUDE.md README.md)
  @document_limit 6_000
  @paths_limit 24_000

  @not_code ~r{(^|/)(node_modules|deps|_build|vendor|dist|build|cover|tmp|\.git|\.github|priv/static|public)/|\.(png|jpe?g|gif|svg|webp|ico|woff2?|ttf|mp3|mp4|wav|ogg|lock|map|po|pot)$}

  @doc "The digest as text for a prompt, or nil when the repository cannot be read."
  @spec read(map(), term()) :: String.t() | nil
  def read(%{owner: owner, name: name}, client) do
    paths = client |> GitHub.tree(owner, name) |> code_paths()
    documents = Enum.flat_map(@documents, &document(client, owner, name, &1))

    Enum.join(["Files:\n" <> Enum.join(paths, "\n") | documents], "\n\n")
  rescue
    exception ->
      Logger.info("repository digest unavailable: #{Exception.message(exception)}")
      nil
  end

  # The shallow files say the most about how a project is laid out, and the
  # budget is spent on them first.
  defp code_paths(tree) do
    tree
    |> Enum.filter(&(&1["type"] == "blob" and not String.match?(&1["path"], @not_code)))
    |> Enum.map(& &1["path"])
    |> Enum.sort_by(&{length(Path.split(&1)), &1})
    |> within_budget()
  end

  defp within_budget(paths) do
    paths
    |> Enum.reduce_while({[], 0}, fn path, {kept, used} ->
      used = used + String.length(path) + 1
      if used > @paths_limit, do: {:halt, {kept, used}}, else: {:cont, {[path | kept], used}}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # Most repositories lack one of these, so a missing file is ordinary.
  defp document(client, owner, name, path) do
    text = client |> GitHub.file_text(owner, name, path) |> String.slice(0, @document_limit)
    ["#{path}:\n#{text}"]
  rescue
    _not_there -> []
  end
end
