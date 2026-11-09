defmodule AgentBoard.System.UpdaterTest do
  @moduledoc "The restart script waits for the old VM and boots the new code."
  use ExUnit.Case, async: false

  alias AgentBoard.System.Updater

  test "waits for the old OS process and refreshes deps and schema" do
    script = Updater.restart_script("/tmp/agent board", "4242")

    assert script =~ "while kill -0 4242 2>/dev/null; do sleep 0.2; done"
    assert script =~ "cd '/tmp/agent board' || exit 1"
    assert script =~ "mix deps.get || exit 1"
    assert script =~ "mix ecto.migrate || exit 1"
    assert script =~ "exec mix phx.server"
  end

  test "supervised mode leaves the restart to the service manager" do
    previous = System.get_env("AGENT_BOARD_RESTART_MODE")
    System.put_env("AGENT_BOARD_RESTART_MODE", "supervised")

    on_exit(fn ->
      if previous,
        do: System.put_env("AGENT_BOARD_RESTART_MODE", previous),
        else: System.delete_env("AGENT_BOARD_RESTART_MODE")
    end)

    assert Updater.restart() == :ok
  end

  test "the restart script promotes the staged build before booting" do
    script = Updater.restart_script("/tmp/agent board", "4242")

    assert script =~ ".agent-board-next-build"
    assert script =~ "mv \"$next_build\" _build"
    assert script =~ "_build/prev"
  end

  test "marks, reads and clears the staged build" do
    dir = Path.join(System.tmp_dir!(), "updater-stage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf!(dir) end)

    assert Updater.pending_build(dir) == nil
    assert Updater.mark_ready(dir) == :ok
    assert Updater.pending_build(dir) == "_build/next"
    assert Updater.clear_marker(dir) == :ok
    assert Updater.pending_build(dir) == nil
  end

  test "quotes a root with a single quote" do
    script = Updater.restart_script("/tmp/it's board", "7")

    assert script =~ "cd '/tmp/it'\\''s board' || exit 1"
  end
end
