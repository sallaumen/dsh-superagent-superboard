defmodule AgentBoard.AgentWorktreeTest do
  @moduledoc "The observed step comes from the worktree, and an absent one is nil, not a guess."
  use ExUnit.Case, async: true

  alias AgentBoard.AgentWorktree

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "agent-worktree-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    git!(dir, ["init", "-q"])
    git!(dir, ["config", "user.email", "agent@example.test"])
    git!(dir, ["config", "user.name", "Agent"])
    File.write!(Path.join(dir, "arena.ex"), "defmodule Arena do\nend\n")
    git!(dir, ["add", "arena.ex"])
    git!(dir, ["commit", "-qm", "Initial arena"])

    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "an uncommitted edit is the current step", %{dir: dir} do
    File.write!(Path.join(dir, "hud.ex"), "defmodule Hud do\nend\n")

    assert %{kind: :edit, code: "hud.ex"} =
             AgentWorktree.step(%{"execution" => %{"directory" => dir}})
  end

  test "with a clean tree the last commit is the step", %{dir: dir} do
    assert %{kind: :commit, code: sha, note: "Initial arena"} =
             AgentWorktree.step(%{"execution" => %{"directory" => dir}})

    assert sha =~ ~r/^[0-9a-f]{7,}$/
  end

  test "no worktree is no step" do
    assert AgentWorktree.step(%{"execution" => %{"directory" => "/does/not/exist"}}) == nil
    assert AgentWorktree.step(%{}) == nil
  end

  defp git!(dir, args) do
    {output, 0} = System.cmd("git", ["-C", dir | args], stderr_to_stdout: true)
    output
  end
end
