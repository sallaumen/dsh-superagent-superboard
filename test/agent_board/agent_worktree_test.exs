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

  test "the newest uncommitted file is the last activity", %{dir: dir} do
    at = ~U[2026-11-06 12:00:00Z]
    File.write!(Path.join(dir, "hud.ex"), "defmodule Hud do\nend\n")
    File.touch!(Path.join(dir, "hud.ex"), DateTime.to_unix(at))

    assert AgentWorktree.last_activity_at(%{"execution" => %{"directory" => dir}}) == at
  end

  test "with a clean tree the last commit is the last activity", %{dir: dir} do
    File.write!(Path.join(dir, "arena.ex"), "defmodule Arena do\n  def hp, do: 1\nend\n")
    git!(dir, ["add", "arena.ex"])

    git!(dir, ["commit", "-qm", "More arena"],
      env: [{"GIT_COMMITTER_DATE", "2026-11-06T13:30:00Z"}]
    )

    assert AgentWorktree.last_activity_at(%{"execution" => %{"directory" => dir}}) ==
             ~U[2026-11-06 13:30:00Z]
  end

  test "no worktree is no activity" do
    assert AgentWorktree.last_activity_at(%{"execution" => %{"directory" => "/does/not/exist"}}) ==
             nil

    assert AgentWorktree.last_activity_at(%{}) == nil
  end

  defp git!(dir, args, opts \\ []) do
    env = Keyword.get(opts, :env, [])
    {output, 0} = System.cmd("git", ["-C", dir | args], stderr_to_stdout: true, env: env)
    output
  end
end
