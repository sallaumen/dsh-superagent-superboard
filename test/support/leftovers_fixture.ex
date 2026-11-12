defmodule AgentBoard.LeftoversFixture do
  @moduledoc """
  An agent's state folder on a temporary disk, for the tests of
  `AgentBoard.Superagents.Leftovers`: a real git checkout, one worktree per
  ticket under `work/` and the agent's sqlite database naming them. The real
  `scripts/agent/cleanup.sh` runs against it.

  The tickets: `old` ended 40 days ago, `recent` 2 days ago, `dirty` 40 days
  ago with an uncommitted file, `open` has not ended. `stray` is a folder no
  ticket names. Every ended ticket was merged, so no pull request is read.
  """

  @doc "Builds the folder and returns `%{state: dir, dirs: %{name => dir}}`."
  def build!(root) do
    main = Path.join(root, "main")
    state = Path.join(root, "state")
    work = Path.join(state, "work")
    File.mkdir_p!(main)
    File.mkdir_p!(work)

    git!(main, ~w(init -q))
    git!(main, ~w(-c user.name=t -c user.email=t@t.test commit -q --allow-empty -m base))

    dirs =
      Map.new(~w(old recent dirty open), fn name ->
        dir = Path.join(work, name)
        git!(main, ["worktree", "add", "-q", "-b", "agent/#{name}", dir])
        {name, dir}
      end)

    File.write!(Path.join(dirs["dirty"], "notes.txt"), "not committed\n")
    File.mkdir_p!(Path.join(work, "stray"))

    rows =
      Enum.map_join(
        [{"old", 40}, {"recent", 2}, {"dirty", 40}, {"open", nil}],
        ",",
        fn {name, age} -> "('#{name}-id', '#{ticket(name, dirs[name], age)}')" end
      )

    sql =
      "CREATE TABLE ticket (id TEXT PRIMARY KEY, value TEXT); INSERT INTO ticket VALUES #{rows};"

    {_output, 0} = System.cmd("sqlite3", [Path.join(state, "orchestrator.sqlite"), sql])

    %{state: state, dirs: Map.put(dirs, "stray", Path.join(work, "stray"))}
  end

  defp ticket(name, dir, age) do
    ended =
      if age do
        at = DateTime.utc_now() |> DateTime.add(-age * 86_400, :second) |> DateTime.to_iso8601()
        %{"ended" => %{"outcome" => "merged", "at" => at, "by" => "agent"}}
      else
        %{}
      end

    Jason.encode!(Map.merge(%{"execution" => %{"name" => name, "directory" => dir}}, ended))
  end

  defp git!(dir, args) do
    {_output, 0} = System.cmd("git", ["-C", dir | args], stderr_to_stdout: true)
    :ok
  end
end
