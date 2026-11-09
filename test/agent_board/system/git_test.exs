defmodule AgentBoard.System.GitTest do
  @moduledoc "The git reads the version panel needs, against this checkout."
  use ExUnit.Case, async: true

  alias AgentBoard.System.Git

  test "head is a short sha" do
    assert {:ok, sha} = Git.head()
    assert sha =~ ~r/^[0-9a-f]{7,}$/
  end

  test "the project root is the checkout mix runs from" do
    assert File.dir?(Git.root())
    assert File.exists?(Path.join(Git.root(), "mix.exs"))
  end

  test "dirty? answers a boolean, never raises" do
    assert is_boolean(Git.dirty?())
  end

  test "commits between two revisions carry the sha and title" do
    assert {:ok, [commit]} = Git.commits("HEAD~1", "HEAD")
    assert commit.sha =~ ~r/^[0-9a-f]{7,}$/
    assert is_binary(commit.title)
  end

  test "a missing revision is an empty list, not a crash" do
    assert {:ok, []} = Git.commits(nil, "HEAD")
    assert {:ok, []} = Git.commits("HEAD", nil)
    assert {:ok, []} = Git.commits("HEAD", "HEAD")
  end

  test "an unknown command is an error, not a crash" do
    assert {:error, _} = Git.run(["not-a-git-command"])
  end
end
