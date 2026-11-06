defmodule AgentBoard.System.UpdaterTest do
  @moduledoc "The restart script waits for the old VM and boots the new code."
  use ExUnit.Case, async: true

  alias AgentBoard.System.Updater

  test "waits for the old OS process and refreshes deps and schema" do
    script = Updater.restart_script("/tmp/agent board", "4242")

    assert script =~ "while kill -0 4242 2>/dev/null; do sleep 0.2; done"
    assert script =~ "cd '/tmp/agent board' || exit 1"
    assert script =~ "mix deps.get || exit 1"
    assert script =~ "mix ecto.migrate || exit 1"
    assert script =~ "exec mix phx.server"
  end

  test "quotes a root with a single quote" do
    script = Updater.restart_script("/tmp/it's board", "7")

    assert script =~ "cd '/tmp/it'\\''s board' || exit 1"
  end
end
